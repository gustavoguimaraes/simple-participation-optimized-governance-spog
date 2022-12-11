// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IERC20 {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function mint(uint256 amount) external;

    function totalSupply() external view returns (uint256);
}

interface IAuction {
    function sell(uint256 amount) external;
}

/**
 * @title SPOG
 * @dev A governance contract that allows users to stake tokens and vote on proposals
 * @dev Reference: https://hackmd.io/6Y8x2jL1R0CBo6RRBESpLA?both
 * @notice This contract is an imcomplete version from the SPOG doc. It is missing the following: GRIEF and BUYOUT functionalities.
 * A Simple Participation Optimized Governance (“SPOG”) contract minimizes the consensus surface to a binary choice on the following:
 * - Call or do not call arbitrary code
 *
 * In order to deploy an SPOG contract, the creator must first input an ERC20 token address (the token can be specific to the SPOG or an existing ERC20) along with the following arguments, which are immutable. Additionally, all SPOGs should be endowed with a purpose that is ideally a single sentence.
 *
 * Arguments:
 *
 * - TOKEN
 *   - The ERC20 address that will be used to govern the SPOG
 *   - Can be an existing token (e.g. WETH) or a SPOG-specific token
 * - TAX
 *   - The cost, in CASH to call VOTE
 * - CASH
 *   - ERC20 token address to be used for SELL and TAX (e.g. DAI or WETH)
 * - TIME
 *   - The duration of a vote
 * - INFLATOR
 *   - The percentage supply increase in SFG tokens each time VOTE is called
 *
 * SPOG token holders are likened to “nodes” in a decentralized consensus mechanism and are therefore punished for being “offline.”
 */
contract SPOG {
    // Address of the ERC20 token used for staking and voting
    IERC20 public token;

    // Cost to call the vote function, in the CASH token
    uint256 public tax;

    // Address of the ERC20 token used for the tax and sell functions
    IERC20 public cash;

    // Duration of a vote in seconds
    uint256 public time;

    // Timestamp of the end of the staking period
    uint256 public endOfStakingPeriod;

    // Percentage supply increase in SPOG tokens each time vote is called
    uint256 public inflator;

    // Mapping of request IDs to request details
    mapping(bytes32 => Request) public requests;

    // Request struct
    struct Request {
        // Request ID
        bytes32 id;
        // Request proposer
        address proposer;
        // proposal target
        address target;
        // Request description
        string description;
        // Request end time
        uint256 endTime;
        // Request votes for
        uint256 votesFor;
        // Request votes against
        uint256 votesAgainst;
        // Request proposal
        bytes proposalChange;
        // Request result
        VoteOptions result;
        // Request executed
        bool executed;
    }

    enum VoteOptions {
        Unfinished,
        For,
        Against
    }

    // Request counter
    uint256 public totalStakedTokens;

    // Mapping of user addresses to their staked token balance
    mapping(address => uint256) public stakedTokenBalances;

    // Mapping of user addresses to their SPOG token balance
    mapping(address => uint256) public spogTokenBalances;

    // Mapping of user addresses to their voted requests
    mapping(address => mapping(bytes32 => bool)) public userVotes;

    // Mapping of user addresses to their claimed SPOG tokens for voting on requests
    mapping(address => mapping(bytes32 => bool)) public userClaims;

    // Mapping of requests to claimable tokens from inflating the supply
    mapping(bytes32 => uint256) public claimableTokens;

    // Address of the auction contract or AMM contract
    IAuction public auctionContract;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RequestMade(
        bytes32 indexed id,
        address indexed user,
        string description
    );
    event VoteCast(bytes32 indexed id, address indexed user, VoteOptions vote);
    event ClaimInquired(
        bytes32 indexed id,
        address indexed user,
        uint256 amount
    );
    event UnclaimedSold(bytes32 indexed id, uint256 amount);
    event SellTriggered(bytes32 indexed id, uint256 amount);
    event RequestExecuted(bytes32 indexed id, bool result);

    // Constructor
    constructor(
        address _token,
        uint256 _tax,
        address _cash,
        uint256 _time,
        uint256 _inflator,
        address _auctionContract
    ) {
        require(_token != address(0), "Token address cannot be zero");
        require(_cash != address(0), "Cash address cannot be zero");
        require(
            _auctionContract != address(0),
            "Auction address cannot be zero"
        );

        token = IERC20(_token);
        tax = _tax;
        cash = IERC20(_cash);
        time = _time;
        endOfStakingPeriod = block.timestamp + time;
        inflator = _inflator;
        auctionContract = IAuction(_auctionContract);
    }

    /// @dev stake function to stake SPOG tokens
    /// @param _amount The amount of tokens to stake
    function stake(uint256 _amount) public {
        require(
            block.timestamp <= endOfStakingPeriod,
            "Staking period has ended"
        );
        require(
            token.balanceOf(msg.sender) >= _amount,
            "Insufficient balance in token contract"
        );

        // Transfer the tokens from the user to the contract
        token.transferFrom(msg.sender, address(this), _amount);

        // Add the tokens to the user's staked balance
        stakedTokenBalances[msg.sender] += _amount;
        totalStakedTokens += _amount;

        // Add the tokens to the user's SPOG balance. This is deducted when unstaking
        spogTokenBalances[msg.sender] += _amount;

        emit Staked(msg.sender, _amount);
    }

    /// @dev unstake tokens
    /// @param _amount The amount of tokens to unstake
    function unstake(uint256 _amount) public {
        require(
            block.timestamp > endOfStakingPeriod,
            "Staking period has not ended"
        );
        require(
            spogTokenBalances[msg.sender] >= _amount,
            "Insufficient balance staked"
        );

        // Subtract the tokens from the user's SPOG staked token balance. The stakedTokenBalances mapping is not updated as it will be needed for voting
        spogTokenBalances[msg.sender] -= _amount;

        // Transfer the tokens from the contract to the user
        token.transfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    /// @dev make a request to governance to change a target contract. This initiates a vote.
    /// Triggers an INFLATOR increase in the SPOG_ERC20 supply. Must include the proposed change and target.
    /// @param _target The address of the target contract
    /// @param _description The description of the request
    /// @param _proposalChange The proposal change to be made to the target contract
    function createRequest(
        address _target,
        string memory _description,
        bytes memory _proposalChange
    ) public {
        require(
            block.timestamp <= endOfStakingPeriod,
            "Staking period has not ended"
        );
        require(
            cash.balanceOf(msg.sender) >= tax,
            "Insufficient balance in cash contract"
        );
        require(_target != address(0), "Target address cannot be zero");
        require(_proposalChange.length != 0, "Proposal cannot be empty");

        // Get the request ID
        bytes32 id = keccak256(
            abi.encodePacked(_target, _description, _proposalChange)
        );

        // Check if the request already exists
        require(requests[id].endTime == 0, "Request already exists");

        // Transfer the tax from the user to the contract
        cash.transferFrom(msg.sender, address(this), tax);

        // Create the request
        requests[id] = Request({
            id: id,
            proposer: msg.sender,
            target: _target,
            description: _description,
            endTime: block.timestamp + time,
            votesFor: 0,
            votesAgainst: 0,
            proposalChange: _proposalChange,
            result: VoteOptions.Unfinished,
            executed: false
        });

        // trigger an inflation increase in the SPOG token supply
        uint256 amount = (token.totalSupply() * inflator) / 100;
        claimableTokens[id] = amount;
        token.mint(amount);

        // Emit the RequestMade event
        emit RequestMade(id, msg.sender, _description);
    }

    /// @dev make multiple requests at once
    /// @param _targets the targets of the requests
    /// @param _descriptions the descriptions of the requests
    /// @param _proposalChanges the proposal changes of the requests
    function createRequests(
        address[] memory _targets,
        string[] memory _descriptions,
        bytes[] memory _proposalChanges
    ) external {
        require(
            _targets.length == _descriptions.length &&
                _targets.length == _proposalChanges.length,
            "Array lengths do not match"
        );

        // Loop through the targets, descriptions and proposalChanges arrays
        uint256 length = _targets.length;
        for (uint256 i = 0; i < length; ) {
            // Make the request
            createRequest(_targets[i], _descriptions[i], _proposalChanges[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev execute proposal change from a request on the request's target contract
    /// @param _id the ID of the request
    function executeRequest(bytes32 _id) external {
        require(
            block.timestamp > endOfStakingPeriod,
            "Staking period has not ended"
        );
        require(
            requests[_id].endTime != 0,
            "Request does not exist or has expired"
        );
        require(
            requests[_id].endTime < block.timestamp,
            "Request has not expired"
        );
        require(
            requests[_id].result != VoteOptions.Unfinished,
            "Request has not been voted on"
        );
        require(
            requests[_id].result == VoteOptions.For,
            "Request has not received enough votes"
        );
        require(
            requests[_id].executed == false,
            "Request has already been executed"
        );

        // Update the request's executed status
        requests[_id].executed = true;

        // Call the target contract with the proposal change
        (bool success, ) = requests[_id].target.call(
            requests[_id].proposalChange
        );

        require(success, "Proposal change failed");

        // Emit the RequestExecuted event
        emit RequestExecuted(_id, success);
    }

    /// @dev vote on a request. Must be called within time period and user must have staked tokens
    /// @param _id the request id
    /// @param _vote the vote option
    function vote(bytes32 _id, VoteOptions _vote) external {
        require(
            block.timestamp <= endOfStakingPeriod,
            "Staking period has not ended"
        );
        require(
            requests[_id].endTime != 0,
            "Request does not exist or has expired"
        );
        require(requests[_id].endTime > block.timestamp, "Request has expired");
        require(
            userVotes[msg.sender][_id] == false,
            "User has already voted on this request"
        );

        // Update the user's vote status
        userVotes[msg.sender][_id] = true;

        // Update the request's vote count
        if (_vote == VoteOptions.For) {
            requests[_id].votesFor += stakedTokenBalances[msg.sender];
        } else {
            requests[_id].votesAgainst += stakedTokenBalances[msg.sender];
        }

        // Emit the VoteCast event
        emit VoteCast(_id, msg.sender, _vote);
    }

    /// @dev claim tokens. Allows SPOG_ERC20 holders to claim their pro-rata share of the newly minted supply of SPOG tokens
    /// Must be called within time period after staking period ends
    /// @param requestId the id of the request to claim tokens for
    function claim(bytes32 requestId) public {
        require(
            block.timestamp > endOfStakingPeriod,
            "Staking period has not ended"
        );
        require(
            block.timestamp <= endOfStakingPeriod + time,
            "Claim period has ended"
        );
        require(
            stakedTokenBalances[msg.sender] > 0,
            "User has not staked any tokens"
        );
        require(
            userVotes[msg.sender][requestId] == true,
            "User has not voted on any requests"
        );
        require(
            userClaims[msg.sender][requestId] == false,
            "User has already claimed"
        );
        // update user's claim status
        userClaims[msg.sender][requestId] = true;

        // get the claimable tokens
        uint256 _claimableTokens = claimableTokens[requestId];

        // Get the user's staked token balance
        uint256 stakedBalance = stakedTokenBalances[msg.sender];

        // calculate user's share of claimable tokens
        uint256 share = (_claimableTokens * stakedBalance) / totalStakedTokens;

        // update global claimable tokens
        claimableTokens[requestId] = claimableTokens[requestId] - share;

        // Transfer the share of newly minted tokens to the caller
        token.transfer(msg.sender, share);

        // Emit the ClaimInquired event
        emit ClaimInquired(requestId, msg.sender, share);
    }

    /// @dev claim all tokens from requests in an array
    /// @param requestIds the array of request ids
    function claimAll(bytes32[] memory requestIds) external {
        // Loop through the requestIds array and claim tokens for each request
        uint256 length = requestIds.length;
        for (uint256 i = 0; i < length; ) {
            // Make the claim
            claim(requestIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev sell unclaimed tokens
    /// Callable on a REQUEST after TIME and causes unclaimed SPOG_ERC20 to be sold through the auction contract
    /// @param _id the id of the request
    function sellUnclaimed(bytes32 _id) public {
        require(
            block.timestamp > endOfStakingPeriod,
            "Staking period has not ended"
        );
        require(
            block.timestamp > endOfStakingPeriod + time,
            "Claim period has not ended"
        );
        require(
            requests[_id].endTime != 0,
            "Request does not exist or has expired"
        );
        require(
            block.timestamp > requests[_id].endTime,
            "Request has not expired"
        );

        uint256 _claimableTokens = claimableTokens[_id];

        // zero global claimable tokens for request
        claimableTokens[_id] = claimableTokens[_id] - _claimableTokens;

        // calculate the amount of unclaimed tokens
        uint256 unclaimedTokens = _claimableTokens -
            (requests[_id].votesFor + requests[_id].votesAgainst);

        // call auction contract to sell unclaimed tokens
        auctionContract.sell(unclaimedTokens);

        // Transfer the share of newly minted tokens to the caller
        token.transfer(msg.sender, unclaimedTokens);

        // Emit the UnclaimedSold event
        emit UnclaimedSold(_id, unclaimedTokens);
    }

    /// @dev sell unclaimed tokens for all requests in an array
    /// @param requestIds array of requestIds
    function sellUnclaimedForRequests(bytes32[] memory requestIds) external {
        uint256 length = requestIds.length;
        for (uint256 i = 0; i < length; ) {
            sellUnclaimed(requestIds[i]);

            unchecked {
                ++i;
            }
        }
    }
}
