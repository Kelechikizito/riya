# The one-sentence pitch

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
