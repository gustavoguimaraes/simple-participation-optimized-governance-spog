# Simple Participation Optimized Governance (SPOG)

Partial implementation of the SPOG as per this reference [document](https://hackmd.io/6Y8x2jL1R0CBo6RRBESpLA).
It is NOT production ready and is intended for educational purposes only.

**A Simple Participation Optimized Governance ("SPOG")** contract minmizes the consensus surface to a binary choice on the following:

- Call or do not call arbitrary code

In order to deploy an SPOG contract the creator must first input an ERC20 token address (the token can be specific to the SPOG or an existing ERC20) along with the following arguments, which are immutable. Additionally, all SPOGs should be endowed with a purpose that is ideally a single sentence.

## Setup

Clone the repo and install dependencies

```bash
 forge install
```

To build the project

```bash
 forge build
```

### Todos:

[ ]: Complete tests

[ ]: Add GRIEF mechanism

[ ]: Add BUYOUT function

[ ]: Create Mock Auction Contract to Simulate SELL mechanism
