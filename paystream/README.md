# StreamPay: Payment Channel Smart Contract

StreamPay is a state channel implementation that enables real-time micropayments between content creators and viewers. It solves the problem of high-frequency, low-value transactions by taking them off-chain while maintaining security through cryptographic signatures and on-chain settlement.

## 🎯 Use Case: Live Streaming Platform

### Problem
Alice is a content creator who streams educational content. Her viewers want to support her based on actual watch time, but:
- Making an on-chain transaction every minute is expensive and slow
- Monthly subscriptions don't reflect actual usage
- Tipping is manual and interrupts viewing experience

### Solution
Using StreamPay:
1. Bob (viewer) opens a payment channel with Alice by depositing 100 STX
2. While watching:
   - Every minute, Bob's client signs a new state giving Alice 0.1 STX
   - No on-chain transactions occur during streaming
   - Alice can verify Bob's commitment in real-time
3. After the session:
   - If Bob watched for 30 minutes, the final state shows 3 STX for Alice
   - Either party can close the channel with the latest signed state
   - Funds are distributed according to the agreed amounts

## 📋 Features

- **Instant Payments**: No confirmation times for intermediate states
- **Low Fees**: Only opening and closing transactions incur blockchain fees
- **Safety**: Funds are secured by smart contract and cryptographic signatures
- **Dispute Resolution**: Built-in timeout mechanism for uncooperative parties
- **Flexible Updates**: Support for multiple state updates with nonce tracking
- **Two-Way Channel**: Both creator and viewer balances can be adjusted

## 🔧 Technical Architecture

### Data Structures

```clarity
;; Channel information
channels: {
  channel-id → {
    viewer: principal,
    creator: principal,
    viewer-balance: uint,
    creator-balance: uint,
    total-deposit: uint,
    nonce: uint,
    timeout-height: uint,
    is-active: bool
  }
}

;; Channel states with signatures
channel-states: {
  (channel-id, nonce) → {
    viewer-balance: uint,
    creator-balance: uint,
    viewer-sig: optional buff,
    creator-sig: optional buff
  }
}
```

### Core Functions

1. **Channel Management**
   - `create-channel`: Open new payment channel
   - `close-channel`: Cooperative closure
   - `dispute-channel`: Initiate dispute
   - `settle-disputed-channel`: Force settlement after timeout

2. **State Updates**
   - `propose-update`: Submit new balance allocation
   - `accept-update`: Counter-sign proposed update

## 🚀 Getting Started

### Prerequisites
- Stacks wallet with STX tokens
- [Clarity CLI](https://github.com/hirosystems/clarinet)
- Basic understanding of digital signatures

### Deployment

1. Deploy contract:
```bash
clarinet contract deploy streampay
```

2. Open channel (as viewer):
```clarity
(contract-call? .streampay create-channel 
  'CREATOR_ADDRESS 
  u1000000) ;; 1000000 uSTX = 1 STX
```

3. Update state (off-chain):
```clarity
;; Generate and sign state update
(contract-call? .streampay propose-update 
  channel-id
  nonce
  viewer-balance
  creator-balance
  signature)
```

### Integration Example (Pseudo-code)

```javascript
// Client-side viewer application
class StreamPayClient {
  async startStream(creatorAddress) {
    // Open channel
    const channelId = await createChannel(creatorAddress, initialDeposit);
    
    // Start payment loop
    setInterval(async () => {
      const newState = calculateNewState(watchedMinutes);
      const signature = signState(newState);
      await proposeUpdate(channelId, newState, signature);
    }, 60000); // Every minute
  }
}
```

## ⚠️ Security Considerations

1. **Always verify signatures** before accepting state updates
2. **Monitor channel timeouts** for dispute periods
3. **Keep signed states** until channel is closed
4. **Implement client-side validation** for all state transitions
5. **Maintain nonce order** to prevent replay attacks

## 🔍 Testing

Run the test suite:
```bash
clarinet test
```

Key test scenarios:
- Channel creation and deposit validation
- State update signatures and verification
- Dispute resolution and timeouts
- Balance calculations and constraints
- Error conditions and recovery