# The one-sentence pitch

**Automatic self-repaying loan.**

**You put money to work on Ethereum. You borrow against it on Creditcoin. The
profits your money earns on Ethereum pay off the loan for you, automatically,
until you owe nothing.**

You never make a repayment. You never get liquidated. You just wait.

This is a copy of [Alchemix](https://alchemix.fi), which already proved the idea
works. The new part is that the savings live on **one** chain and the loan lives
on **another**, and Creditcoin can prove what happened on the first chain without
trusting anybody.

## How it works, with real numbers

Say Ada has $1,000 of USDC and wants cash now without selling.

1. **Ada deposits.** She puts $1,000 USDC into _our_ contract on Ethereum. That
   contract parks the money in Aave, where it earns roughly 5% a year.
2. **We prove the deposit.** Our off-chain bot notices the deposit and asks
   Creditcoin to verify it. Creditcoin checks the maths itself and confirms:
   _yes, that deposit really happened on Ethereum._
3. **Ada borrows — but only a little at first.** She is brand new, so her credit
   score is **0** and she can borrow **10%** of her deposit: **$100**. She now
   has spendable money on Creditcoin and a $100 debt.
4. **The money earns.** Ada's $1,000 sits in Aave making about $50 a year.
   Every so often we "harvest" that profit into our Ethereum contract.
5. **Each harvest is proven and wipes out debt.** We prove each harvest to
   Creditcoin the same way as step 2. Creditcoin sees "$25 of real yield
   arrived" and knocks $25 off Ada's debt. No payment from Ada.
6. **Repaying raises her score, which raises her limit.** After $40 is retired her
   score is 20 and her limit moves to 20%; after $170 she is at the 50% ceiling.
   See "The credit score" below.
7. **Eventually the debt hits zero.** Then Ada owes nothing — she can redraw at
   her new limit, or walk away with her $1,000.

Ada never repaid a penny. Her savings did it.

But there is an honest problem, and you should know it before a judge asks. s_protocolFees is a number on Creditcoin representing a claim on USDC sitting in the Ethereum escrow. Paying it out means moving money from Ethereum, which needs the outbound leg. So riya accrues revenue in v1 and cannot collect it.

The fix, and it needs no writability

Mint the fee as RiyaUSD to a treasury address.

This is not creating money from nothing. Look at what your own RiyaUSD NatSpec already says: the full gross harvest lands in the escrow, but only 85% is distributed into s_yieldPerShare. That 15% is real USDC in the escrow with no claim against it. Minting the treasury's RiyaUSD against it consumes exactly that margin. Every token stays backed.

What changes:

solidity
s_protocolFees += fee;
I_RIYA_USD.mint(I_TREASURY, fee);

Revenue becomes a spendable balance on Creditcoin on day one rather than an IOU waiting on a feature that does not exist. That is the difference between "we have a business model" and "we have a business model you can watch working in the demo."

## Demo

Say it out loud in the pitch rather than hoping nobody notices. "We compress a month of yield into one transaction so this fits in five minutes. The adapter is tested against real Aave V4 on a mainnet fork."

Do not discover the length of that wait during the demo. Two mitigations, and I would do both:

- Run the deposit before you start presenting, so collateral is already on Creditcoin when you begin. Demo the harvest leg live, since that is the interesting half anyway.
- Have a recording of a full run as a fallback.

## Hackathon Judging Criterion

