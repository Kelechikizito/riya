##

== Return ==
usd: contract MockUSD 0xDf60fe1644F5b2649188BA79329De505E5e3fC2B
spoke: contract MockAaveSpoke 0xe89649Ed823c18b12c2fAD098ba3cfcB702897Be
reserveId: uint256 1

== Logs ==
recorded : deployments/11155111-mocks.json
MOCK_USD = 0xDf60fe1644F5b2649188BA79329De505E5e3fC2B
MOCK_SPOKE = 0xe89649Ed823c18b12c2fAD098ba3cfcB702897Be
MOCK_RESERVE_ID = 1

## Setting up 1 EVM.

==========================

Chain 11155111

Estimated gas price: 3.020804117 gwei

Estimated total gas used for script: 2844204

Estimated amount required: 0.008591783152787868 ETH

==========================
Enter keystore password:

Transactions saved to: /Users/user/hackathon-projects/riya/broadcast/DeployMocks.s.sol/11155111/run-latest.json

Sensitive values saved to: /Users/user/hackathon-projects/riya/cache/DeployMocks.s.sol/11155111/run-latest.json

## 2

MOCK_USD ok 0xcA1BA8049f1e29c07f539C7c918dcc1D57BF318F
MOCK_SPOKE ok 0xf0f1ea77A624382C3656aE5C4d93dBfEC59e3064
AAVE_V4_ADAPTER_ADDRESS not deployed
RIYA_ESCROW_ADDRESS not deployed
RIYA_USD_ADDRESS not deployed
RIYA_ASC_ADDRESS not deployed
LOAN_LEDGER_ADDRESS not deployed

## 3

== Return ==
adapter: contract AaveV4Adapter 0x83142d63752E09490c4FfCd2482568a7c8618bFb
escrow: contract RiyaEscrow 0xEDe17e550D36597CA497356DBE2CfCebC876b72e
helperConfig: contract HelperConfig 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141

== Logs ==
recorded : deployments/11155111-source.json
deployer : 0xDBC29E79b2B3b62C015AB598D0bb86681313d90F
adapter : 0x83142d63752E09490c4FfCd2482568a7c8618bFb
escrow : 0xEDe17e550D36597CA497356DBE2CfCebC876b72e

## 4

user@Kaykays-MacBook-Air riya % make verify-addresses
MOCK_USD ok 0xcA1BA8049f1e29c07f539C7c918dcc1D57BF318F
MOCK_SPOKE ok 0xf0f1ea77A624382C3656aE5C4d93dBfEC59e3064
AAVE_V4_ADAPTER_ADDRESS ok 0x83142d63752E09490c4FfCd2482568a7c8618bFb
RIYA_ESCROW_ADDRESS ok 0xEDe17e550D36597CA497356DBE2CfCebC876b72e
RIYA_USD_ADDRESS not deployed
RIYA_ASC_ADDRESS not deployed
LOAN_LEDGER_ADDRESS not deployed

## 5

user@Kaykays-MacBook-Air riya % make deploy-destination
registry [(3, 1, 0x457468657265756d, 1), (1, 11155111 [1.115e7], 0x5365706f6c696120657468657265756d, 1)]
chain key 1 resolves to 11155111, as configured
forge script script/deployment/DeployRiyaDestinationChain.s.sol:DeployRiyaDestinationChain --rpc-url https://rpc.cc3-testnet.creditcoin.network --broadcast --slow --account sepolia-acc --sender 0xDBC29E79b2B3b62C015AB598D0bb86681313d90F --password-file .keystore-password -vvv
[⠒] Compiling...
No files changed, compilation skipped
Script ran successfully.

== Return ==
riyaUSD: contract RiyaUSD 0x194b050678eb50923b84fE5aDC8E6f8176D43335
asc: contract RiyaASC 0xce0c01B9c2E407af328eB25D06aea0f1929aaBC7
ledger: contract LoanLedger 0x551904f44630B7C2ac9BBf81db795928Cc329E86
helperConfig: contract HelperConfigDestination 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141

== Logs ==
recorded : deployments/102031-destination.json
deployer : 0xDBC29E79b2B3b62C015AB598D0bb86681313d90F
riyaUSD : 0x194b050678eb50923b84fE5aDC8E6f8176D43335
asc : 0xce0c01B9c2E407af328eB25D06aea0f1929aaBC7
ledger : 0x551904f44630B7C2ac9BBf81db795928Cc329E86
chainKey : 1
escrow : 0xEDe17e550D36597CA497356DBE2CfCebC876b72e
adapter : 0x83142d63752E09490c4FfCd2482568a7c8618bFb

## 6

user@Kaykays-MacBook-Air riya % make verify-addresses
MOCK_USD ok 0xcA1BA8049f1e29c07f539C7c918dcc1D57BF318F
MOCK_SPOKE ok 0xf0f1ea77A624382C3656aE5C4d93dBfEC59e3064
AAVE_V4_ADAPTER_ADDRESS ok 0x83142d63752E09490c4FfCd2482568a7c8618bFb
RIYA_ESCROW_ADDRESS ok 0xEDe17e550D36597CA497356DBE2CfCebC876b72e
RIYA_USD_ADDRESS ok 0x194b050678eb50923b84fE5aDC8E6f8176D43335
RIYA_ASC_ADDRESS ok 0xce0c01B9c2E407af328eB25D06aea0f1929aaBC7
LOAN_LEDGER_ADDRESS ok 0x551904f44630B7C2ac9BBf81db795928Cc329E86
