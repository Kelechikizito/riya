# riya — build, test, deploy, demo.
#
# Every target that touches a chain reads its endpoint from `.env`, which is gitignored.
# Copy `.env.example` first and fill it in. Addresses printed by the deploy targets go
# back into `.env`, and the interaction targets read them from there.
#
# Two chains, and the distinction runs through everything:
#   Sepolia     — money lives here, contracts only state facts
#   Creditcoin  — proofs land here, and every decision is made here

-include .env

# The deploy scripts write their addresses here, one file per chain and step. Included
# after `.env` so a fresh deployment wins over a stale hand-edited value. Delete a file
# to fall back to `.env`.
-include deployments/*.env

export

.PHONY: help install build fmt fmt-check lint clean snapshot \
        test test-unit test-fuzz test-integration test-fork test-local coverage coverage-report \
        offchain-install offchain-typecheck offchain-test offchain-abi worker keeper worker-once worker-dead keeper-once \
        deploy-mocks deploy-source deploy-destination deploy-all addresses verify-addresses verify-chain-key clean-deployments \
        deposit accrue harvest source-status sender senders unlock preflight require-sender \
        borrow repay settle position \
        demo frontend-env frontend-dev frontend-build anvil

SHELL := /bin/bash

# Keys live in Foundry's encrypted keystore, never in .env and never in a process list.
# Import once with:  cast wallet import <name> --interactive
DEPLOYER_ACCOUNT := sepolia-acc
KEEPER_ACCOUNT   := riya-keeper
WORKER_ACCOUNT   := readability-worker

# Optional, and worth setting before a demo: a file containing only the keystore password,
# with no trailing newline issues to get wrong under pressure. It removes the interactive
# prompt entirely, which is the difference between a deploy that fails on the third attempt
# and one that just runs. Keep it outside the repo; `.keystore-password` is gitignored.
#   printf '%s' 'your-password' > .keystore-password && chmod 600 .keystore-password
KEYSTORE_PASSWORD_FILE ?=
PASSFILE := $(if $(KEYSTORE_PASSWORD_FILE),--password-file $(KEYSTORE_PASSWORD_FILE),)

# `--sender` is required alongside `--account`: forge needs the address during simulation,
# before it unlocks the keystore, and the deploy scripts predict nonces against it. Get it
# with `make sender` and put DEPLOYER_ADDRESS in .env.
SIGNER := --account $(DEPLOYER_ACCOUNT) $(if $(DEPLOYER_ADDRESS),--sender $(DEPLOYER_ADDRESS),) $(PASSFILE)

# Verification is source-chain only, and the key is passed explicitly rather than left to
# foundry.toml's ${ETHERSCAN_API_KEY} placeholder, which `forge config` shows unresolved.
# Unset means deploy unverified rather than fail halfway through a broadcast.
VERIFY := $(if $(ETHERSCAN_API_KEY),--verify --etherscan-api-key $(ETHERSCAN_API_KEY),)

# --slow sends one transaction at a time and waits for each receipt. Required here, not
# optional: an EIP-7702 delegated EOA is limited to one in-flight transaction with no nonce
# gaps, and forge's default parallel submission is rejected with
#   "in-flight transaction limit reached for delegated accounts"
# Check with: cast code <address>   (a delegated account starts 0xef0100)
SEPOLIA_ARGS    := --rpc-url $(ETH_SEPOLIA_RPC_URL) --broadcast --slow $(SIGNER) $(VERIFY)
CREDITCOIN_ARGS := --rpc-url $(CREDITCOIN_RPC_URL) --broadcast --slow $(SIGNER)

# Read-only variants. No broadcast, no keystore unlock, no gas.
READ_SENDER     := $(if $(DEPLOYER_ADDRESS),--sender $(DEPLOYER_ADDRESS),)
SEPOLIA_READ    := --rpc-url $(ETH_SEPOLIA_RPC_URL) $(READ_SENDER)
CREDITCOIN_READ := --rpc-url $(CREDITCOIN_RPC_URL) $(READ_SENDER)

SOURCE_ACTIONS := script/interactions/SourceChainActions.s.sol
DEST_ACTIONS   := script/interactions/DestinationChainActions.s.sol

help:
	@echo "riya"
	@echo ""
	@echo "  setup      install  build  fmt  clean"
	@echo "  test       test  test-unit  test-fuzz  test-integration  test-fork  test-local  coverage"
	@echo "  offchain   offchain-install  offchain-abi  offchain-test  worker  keeper"
	@echo "  deploy     deploy-mocks  deploy-source  deploy-destination  addresses  verify-addresses"
	@echo "             verify-chain-key"
	@echo "  sepolia    deposit  accrue  harvest  source-status"
	@echo "  creditcoin borrow  repay  settle  position"
	@echo "  demo       demo  frontend-env  frontend-dev"
	@echo ""
	@echo "  Keys come from the Foundry keystore: $(DEPLOYER_ACCOUNT), $(KEEPER_ACCOUNT), $(WORKER_ACCOUNT)."
	@echo "  Run 'make senders' once and put the three addresses in .env."
	@echo "  'make unlock' checks the keystore password without spending anything."
	@echo ""
	@echo "  Amounts are in USDC's 6 decimals. Override with AMOUNT=..., e.g."
	@echo "    make deposit AMOUNT=500000000     # \$$500"
	@echo "    make borrow  AMOUNT=50000000      # \$$50"

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

install:
	forge install
	npm install

build:
	forge build

fmt:
	forge fmt

fmt-check:
	forge fmt --check

clean:
	forge clean

snapshot:
	forge snapshot

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test:
	forge test

test-unit:
	forge test --match-path "test/unit/*"

test-fuzz:
	forge test --match-path "test/fuzz/*"

test-integration:
	forge test --match-path "test/integration/*"

# Needs ETH_MAINNET_RPC_URL and CREDITCOIN_RPC_URL. Slower than the rest.
test-fork:
	forge test --match-path "test/fork/*" --match-contract CreditcoinTestnetForkTest -vv

# Everything that needs no network at all.
test-local:
	forge test --no-match-path "{test/fork/*,test/unit/RiyaEscrowMainnetTest.t.sol}"

# `script/` and `test/` are excluded from the report, not from execution.
coverage:
	forge coverage --no-match-coverage "(test|node_modules)"

coverage-report:
	forge coverage --no-match-coverage "(test|node_modules)" --report lcov
	@echo "wrote lcov.info"

# ---------------------------------------------------------------------------
# Off-chain (keeper and readability worker)
# ---------------------------------------------------------------------------

offchain-install:
	npm --prefix offchain install

# Regenerates offchain/src/abi.ts from Foundry's out/. Run after any contract change.
offchain-abi: build
	npm --prefix offchain run abi

offchain-typecheck:
	npm --prefix offchain run typecheck

offchain-test:
	npm --prefix offchain test

# The off-chain programs are TypeScript and cannot read Foundry's keystore, so the key is
# decrypted here and handed over for the life of the process. It never reaches .env and
# never reaches disk. Each of these prompts for the keystore password.
WORKER_KEY = WORKER_PRIVATE_KEY=$$(cast wallet decrypt-keystore $(WORKER_ACCOUNT) | awk '{print $$NF}')
KEEPER_KEY = KEEPER_PRIVATE_KEY=$$(cast wallet decrypt-keystore $(KEEPER_ACCOUNT) | awk '{print $$NF}')

# The readability worker. Watches Sepolia, waits for attestation, proves to RiyaASC.
worker:
	@$(WORKER_KEY) npm --prefix offchain run worker

# Prove one transaction and exit. TX=0x...
worker-once:
	@$(WORKER_KEY) npm --prefix offchain run worker -- --once $(TX)

# Reads the local store only, so it needs no key.
worker-dead:
	npm --prefix offchain run worker -- --dead

# The keeper. Polls yieldAccrued() and calls harvest() when it clears the floor.
# Its default interval is five minutes, which is too slow to watch. For a demo:
#   make keeper KEEPER_POLL_INTERVAL_MS=15000
keeper:
	@$(KEEPER_KEY) npm --prefix offchain run keeper

keeper-once:
	@$(KEEPER_KEY) npm --prefix offchain run keeper -- --once

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

# The deployer's address, for DEPLOYER_ADDRESS in .env. Prompts for the password.
sender:
	@cast wallet address --account $(DEPLOYER_ACCOUNT) $(PASSFILE)

# Checks the password decrypts, and that the account it unlocks is the one .env expects.
# Costs nothing, and catches a wrong password before a deploy spends four minutes reaching
# the signing step. Run it whenever a deploy fails with "incorrect password".
unlock:
	@addr=$$(cast wallet address --account $(DEPLOYER_ACCOUNT) $(PASSFILE) 2>&1); \
	if [ "$${addr#0x}" = "$$addr" ]; then echo "  password REJECTED for $(DEPLOYER_ACCOUNT)"; echo "  $$addr"; exit 1; fi; \
	echo "  $(DEPLOYER_ACCOUNT)  unlocks $$addr"; \
	if [ -n "$(DEPLOYER_ADDRESS)" ] && [ "$$addr" != "$(DEPLOYER_ADDRESS)" ]; then \
	  echo "  MISMATCH: .env says $(DEPLOYER_ADDRESS)"; exit 1; fi

# All three, for .env. Three prompts. Only the deployer's is load-bearing; the other two
# exist so `preflight` can check that the keeper and worker are funded.
senders:
	@printf "DEPLOYER_ADDRESS=%s\n" "$$(cast wallet address --account $(DEPLOYER_ACCOUNT))"
	@printf "KEEPER_ADDRESS=%s\n"   "$$(cast wallet address --account $(KEEPER_ACCOUNT))"
	@printf "WORKER_ADDRESS=%s\n"   "$$(cast wallet address --account $(WORKER_ACCOUNT))"

# Every broadcasting target depends on this. Without --sender, forge simulates as its own
# default address and the nonce prediction points at a contract nobody deploys.
require-sender:
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then \
	  echo "DEPLOYER_ADDRESS is not set."; \
	  echo "Run 'make sender' and put the address in .env, then try again."; \
	  exit 1; fi

# Everything that has to be true before spending gas. Costs nothing.
preflight:
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then echo "  DEPLOYER_ADDRESS  missing   run: make sender"; \
	  else echo "  DEPLOYER_ADDRESS  $(DEPLOYER_ADDRESS)"; fi
	@if [ -z "$(ETHERSCAN_API_KEY)" ]; then echo "  ETHERSCAN_API_KEY missing   source contracts will deploy unverified"; \
	  else echo "  ETHERSCAN_API_KEY set"; fi
	@if [ -n "$(DEPLOYER_ADDRESS)" ]; then \
	  echo "  deployer sepolia  $$(cast balance $(DEPLOYER_ADDRESS) --rpc-url $(ETH_SEPOLIA_RPC_URL) --ether 2>/dev/null || echo unreachable) ETH"; \
	  echo "  deployer cc       $$(cast balance $(DEPLOYER_ADDRESS) --rpc-url $(CREDITCOIN_RPC_URL) --ether 2>/dev/null || echo unreachable) tCTC"; fi
	@if [ -z "$(KEEPER_ADDRESS)" ]; then echo "  keeper            unknown     run: make senders"; \
	  else echo "  keeper sepolia    $$(cast balance $(KEEPER_ADDRESS) --rpc-url $(ETH_SEPOLIA_RPC_URL) --ether 2>/dev/null || echo unreachable) ETH   pays for harvest"; fi
	@if [ -z "$(WORKER_ADDRESS)" ]; then echo "  worker            unknown     run: make senders"; \
	  else echo "  worker cc         $$(cast balance $(WORKER_ADDRESS) --rpc-url $(CREDITCOIN_RPC_URL) --ether 2>/dev/null || echo unreachable) tCTC  pays for proofs"; fi
	@cast wallet list 2>/dev/null | grep -qx "$(DEPLOYER_ACCOUNT) (Local)" \
	  && echo "  keystore          $(DEPLOYER_ACCOUNT), $(KEEPER_ACCOUNT), $(WORKER_ACCOUNT)" \
	  || echo "  keystore          $(DEPLOYER_ACCOUNT) NOT FOUND"

# 1. Sepolia stand-ins for USDC and the Aave V4 Spoke. Aave V4 is mainnet-only.
#    Put MOCK_USD, MOCK_SPOKE and MOCK_RESERVE_ID in .env afterwards.
deploy-mocks: require-sender
	forge script script/deployment/DeployMocks.s.sol:DeployMocks $(SEPOLIA_ARGS) -vvv

# 2. The Ethereum leg. Reads MOCK_SPOKE / MOCK_RESERVE_ID from .env.
#    Put RIYA_ESCROW_ADDRESS and AAVE_V4_ADAPTER_ADDRESS in .env afterwards.
deploy-source: require-sender
	forge script script/deployment/DeployRiyaSourceChain.s.sol:DeployRiyaSourceChain $(SEPOLIA_ARGS) -vvv

# The chain key is the single most dangerous constant in the project: RiyaASC cannot tell 1
# from 3, the value is immutable, and a wrong one reads the wrong chain forever. The check
# cannot live inside the script, because `forge script` simulates locally and Creditcoin's
# precompiles are native node code with no bytecode to fetch. `cast call` reaches the node,
# so that is where it belongs.
CHAIN_INFO_PRECOMPILE := 0x0000000000000000000000000000000000000fD3

# Sepolia's key in Creditcoin Testnet's registry, and the chain id it must resolve to.
# `.env` wins if it sets CHAIN_KEY, since the worker reads the same variable.
CHAIN_KEY             ?= 1
CHAIN_KEY_EXPECTS     := 11155111

verify-chain-key:
	@raw=$$(cast call $(CHAIN_INFO_PRECOMPILE) "get_supported_chains()" --rpc-url $(CREDITCOIN_RPC_URL)); \
	decoded=$$(cast decode-abi "get_supported_chains()((uint64,uint64,bytes,uint8)[])" "$$raw"); \
	echo "  registry          $$decoded"; \
	if echo "$$decoded" | grep -q "($(CHAIN_KEY), $(CHAIN_KEY_EXPECTS)"; then \
	  echo "  chain key $(CHAIN_KEY)       resolves to $(CHAIN_KEY_EXPECTS), as configured"; \
	else \
	  echo "  chain key $(CHAIN_KEY)       DOES NOT resolve to $(CHAIN_KEY_EXPECTS) on this network"; \
	  exit 1; fi

# 3. The Creditcoin leg. Reads the two addresses above. The chain key is checked first,
#    against the live registry, because it is immutable once the ASC is deployed.
deploy-destination: require-sender verify-chain-key
	forge script script/deployment/DeployRiyaDestinationChain.s.sol:DeployRiyaDestinationChain $(CREDITCOIN_ARGS) -vvv

# Ordered, and nothing to paste: each step records its addresses under deployments/,
# which the include above picks up for the next one.
deploy-all:
	@echo "Run these in order. Each records its addresses for the next:"
	@echo "  make deploy-mocks        -> MOCK_USD, MOCK_SPOKE, MOCK_RESERVE_ID"
	@echo "  make deploy-source       -> RIYA_ESCROW_ADDRESS, AAVE_V4_ADAPTER_ADDRESS"
	@echo "  make deploy-destination  -> RIYA_USD_ADDRESS, RIYA_ASC_ADDRESS, LOAN_LEDGER_ADDRESS"
	@echo "  make addresses           -> everything deployed so far"

# Everything recorded, per chain and step. One shell block so the guard actually guards.
addresses:
	@if ! ls deployments/*.json >/dev/null 2>&1; then \
	  echo "Nothing deployed yet. Start with: make deploy-mocks"; \
	else \
	  for f in deployments/*.json; do \
	    echo ""; echo "$$f"; \
	    jq -r 'to_entries[] | "  \(.key) = \(.value)"' "$$f"; \
	  done; echo ""; \
	fi

# A record is written while the script runs, before its transactions confirm. A broadcast
# that fails afterwards leaves a record of a deployment that is not on chain. This is the
# only thing that catches that, so run it after every deploy.
verify-addresses:
	@$(MAKE) --no-print-directory _verify NAME="MOCK_USD"                ADDR="$(MOCK_USD)"                RPC="$(ETH_SEPOLIA_RPC_URL)"
	@$(MAKE) --no-print-directory _verify NAME="MOCK_SPOKE"              ADDR="$(MOCK_SPOKE)"              RPC="$(ETH_SEPOLIA_RPC_URL)"
	@$(MAKE) --no-print-directory _verify NAME="AAVE_V4_ADAPTER_ADDRESS" ADDR="$(AAVE_V4_ADAPTER_ADDRESS)" RPC="$(ETH_SEPOLIA_RPC_URL)"
	@$(MAKE) --no-print-directory _verify NAME="RIYA_ESCROW_ADDRESS"     ADDR="$(RIYA_ESCROW_ADDRESS)"     RPC="$(ETH_SEPOLIA_RPC_URL)"
	@$(MAKE) --no-print-directory _verify NAME="RIYA_USD_ADDRESS"        ADDR="$(RIYA_USD_ADDRESS)"        RPC="$(CREDITCOIN_RPC_URL)"
	@$(MAKE) --no-print-directory _verify NAME="RIYA_ASC_ADDRESS"        ADDR="$(RIYA_ASC_ADDRESS)"        RPC="$(CREDITCOIN_RPC_URL)"
	@$(MAKE) --no-print-directory _verify NAME="LOAN_LEDGER_ADDRESS"     ADDR="$(LOAN_LEDGER_ADDRESS)"     RPC="$(CREDITCOIN_RPC_URL)"

.PHONY: _verify
_verify:
	@if [ -z "$(ADDR)" ]; then printf "  %-24s not deployed\n" "$(NAME)"; \
	elif [ "$$(cast code $(ADDR) --rpc-url $(RPC) 2>/dev/null)" = "0x" ] || [ -z "$$(cast code $(ADDR) --rpc-url $(RPC) 2>/dev/null)" ]; then \
	  printf "  %-24s NO CODE at %s\n" "$(NAME)" "$(ADDR)"; \
	else printf "  %-24s ok  %s\n" "$(NAME)" "$(ADDR)"; fi

# Forgets a deployment. The chain keeps it; you just stop pointing at it.
clean-deployments:
	rm -rf deployments frontend/.env.local
	@echo "cleared deployments/ and frontend/.env.local"

# ---------------------------------------------------------------------------
# Sepolia — where the money is
# ---------------------------------------------------------------------------

# Mint demo dollars and deposit. Emits the event the worker proves. Min $100.
deposit: require-sender
	forge script $(SOURCE_ACTIONS):Deposit $(SEPOLIA_ARGS) -vvv

# The demo's clock. Yield does not accrue with time on a mock reserve.
accrue: require-sender
	forge script $(SOURCE_ACTIONS):AccrueYield $(SEPOLIA_ARGS) -vvv

# Move yield into the escrow. Emits TokensHarvested. The keeper also does this.
harvest: require-sender
	forge script $(SOURCE_ACTIONS):Harvest $(SEPOLIA_ARGS) -vvv

source-status:
	forge script $(SOURCE_ACTIONS):SourceStatus $(SEPOLIA_READ) -vvv

# ---------------------------------------------------------------------------
# Creditcoin — where the decisions are
# ---------------------------------------------------------------------------

# Fails until a deposit proof has landed. That is the design, not a bug.
borrow: require-sender
	forge script $(DEST_ACTIONS):Borrow $(CREDITCOIN_ARGS) -vvv

repay: require-sender
	forge script $(DEST_ACTIONS):Repay $(CREDITCOIN_ARGS) -vvv

# Settlement is lazy. This touches the position so proven yield is applied.
settle: require-sender
	forge script $(DEST_ACTIONS):Settle $(CREDITCOIN_ARGS) -vvv

# Read a position. USER=0x... to inspect someone else's.
position:
	forge script $(DEST_ACTIONS):Position $(CREDITCOIN_READ) -vvv

# ---------------------------------------------------------------------------
# Demo and frontend
# ---------------------------------------------------------------------------

# The run order. Steps 2 and 5 wait on Creditcoin attesting the Sepolia block, so
# start the worker first and do the deposit before you start presenting.
demo:
	@echo "  0.  make worker            # in another terminal, leave it running"
	@echo "  1.  make deposit           # Sepolia. real money, real event"
	@echo "  2.  ...wait for the worker to prove it"
	@echo "  3.  make position          # collateral is now on Creditcoin"
	@echo "  4.  make borrow            # draw against it"
	@echo "  5.  make accrue            # the demo's clock"
	@echo "  6.  make harvest           # yield moves into the escrow on Sepolia"
	@echo "  7.  ...wait for the worker to prove it"
	@echo "  8.  make position          # debt fell without the borrower doing anything"

# Writes frontend/.env.local from whatever is currently recorded, or from .env if a
# deployment predates the record. Run after any deploy.
#
# YIELD_RATE_BPS is defaulted rather than left blank: the frontend reads it with `?? 500`,
# which does not fire on an empty string, so an unset variable would become Number("") = 0
# and every self-repay estimate would read as never.
frontend-env:
	@printf '%s\n' \
	  "NEXT_PUBLIC_LOAN_LEDGER_ADDRESS=$(LOAN_LEDGER_ADDRESS)" \
	  "NEXT_PUBLIC_RIYA_USD_ADDRESS=$(RIYA_USD_ADDRESS)" \
	  "NEXT_PUBLIC_RIYA_ASC_ADDRESS=$(RIYA_ASC_ADDRESS)" \
	  "NEXT_PUBLIC_RIYA_ESCROW_ADDRESS=$(RIYA_ESCROW_ADDRESS)" \
	  "NEXT_PUBLIC_AAVE_ADAPTER_ADDRESS=$(AAVE_V4_ADAPTER_ADDRESS)" \
	  "NEXT_PUBLIC_MOCK_USD_ADDRESS=$(MOCK_USD)" \
	  "NEXT_PUBLIC_CREDITCOIN_RPC_URL=$(CREDITCOIN_RPC_URL)" \
	  "NEXT_PUBLIC_SEPOLIA_RPC_URL=$(ETH_SEPOLIA_RPC_URL)" \
	  "NEXT_PUBLIC_YIELD_RATE_BPS=$(if $(YIELD_RATE_BPS),$(YIELD_RATE_BPS),500)" \
	  > frontend/.env.local
	@echo "wrote frontend/.env.local"

frontend-dev: frontend-env
	npm --prefix frontend run dev

frontend-build: frontend-env
	npm --prefix frontend run build

anvil:
	anvil
