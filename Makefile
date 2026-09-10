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
        deploy-mocks deploy-source deploy-destination deploy-all addresses verify-addresses clean-deployments \
        deposit accrue harvest source-status \
        borrow repay settle position \
        demo frontend-env frontend-dev frontend-build anvil

SHELL := /bin/bash

SEPOLIA_ARGS  := --rpc-url $(ETH_SEPOLIA_RPC_URL) --broadcast --private-key $(PRIVATE_KEY)
CREDITCOIN_ARGS := --rpc-url $(CREDITCOIN_RPC_URL) --broadcast --private-key $(PRIVATE_KEY)

# Read-only variants. No broadcast, no key spent, no gas.
SEPOLIA_READ  := --rpc-url $(ETH_SEPOLIA_RPC_URL)
CREDITCOIN_READ := --rpc-url $(CREDITCOIN_RPC_URL)

SOURCE_ACTIONS := script/interactions/SourceChainActions.s.sol
DEST_ACTIONS   := script/interactions/DestinationChainActions.s.sol

help:
	@echo "riya"
	@echo ""
	@echo "  setup      install  build  fmt  clean"
	@echo "  test       test  test-unit  test-fuzz  test-integration  test-fork  test-local  coverage"
	@echo "  offchain   offchain-install  offchain-abi  offchain-test  worker  keeper"
	@echo "  deploy     deploy-mocks  deploy-source  deploy-destination  addresses  verify-addresses"
	@echo "  sepolia    deposit  accrue  harvest  source-status"
	@echo "  creditcoin borrow  repay  settle  position"
	@echo "  demo       demo  frontend-env  frontend-dev"
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

# The readability worker. Watches Sepolia, waits for attestation, proves to RiyaASC.
worker:
	npm --prefix offchain run worker

# Prove one transaction and exit. TX=0x...
worker-once:
	npm --prefix offchain run worker -- --once $(TX)

# List events the worker gave up on, and why.
worker-dead:
	npm --prefix offchain run worker -- --dead

# The keeper. Polls yieldAccrued() and calls harvest() when it clears the floor.
keeper:
	npm --prefix offchain run keeper

keeper-once:
	npm --prefix offchain run keeper -- --once

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

# 1. Sepolia stand-ins for USDC and the Aave V4 Spoke. Aave V4 is mainnet-only.
#    Put MOCK_USD, MOCK_SPOKE and MOCK_RESERVE_ID in .env afterwards.
deploy-mocks:
	forge script script/deployment/DeployMocks.s.sol:DeployMocks $(SEPOLIA_ARGS) -vvv

# 2. The Ethereum leg. Reads MOCK_SPOKE / MOCK_RESERVE_ID from .env.
#    Put RIYA_ESCROW_ADDRESS and AAVE_V4_ADAPTER_ADDRESS in .env afterwards.
deploy-source:
	forge script script/deployment/DeployRiyaSourceChain.s.sol:DeployRiyaSourceChain $(SEPOLIA_ARGS) -vvv

# 3. The Creditcoin leg. Reads the two addresses above, and asserts the chain key
#    against the live registry before spending any gas.
deploy-destination:
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
deposit:
	forge script $(SOURCE_ACTIONS):Deposit $(SEPOLIA_ARGS) -vvv

# The demo's clock. Yield does not accrue with time on a mock reserve.
accrue:
	forge script $(SOURCE_ACTIONS):AccrueYield $(SEPOLIA_ARGS) -vvv

# Move yield into the escrow. Emits TokensHarvested. The keeper also does this.
harvest:
	forge script $(SOURCE_ACTIONS):Harvest $(SEPOLIA_ARGS) -vvv

source-status:
	forge script $(SOURCE_ACTIONS):SourceStatus $(SEPOLIA_READ) -vvv

# ---------------------------------------------------------------------------
# Creditcoin — where the decisions are
# ---------------------------------------------------------------------------

# Fails until a deposit proof has landed. That is the design, not a bug.
borrow:
	forge script $(DEST_ACTIONS):Borrow $(CREDITCOIN_ARGS) -vvv

repay:
	forge script $(DEST_ACTIONS):Repay $(CREDITCOIN_ARGS) -vvv

# Settlement is lazy. This touches the position so proven yield is applied.
settle:
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
	  "NEXT_PUBLIC_YIELD_RATE_BPS=$(YIELD_RATE_BPS)" \
	  > frontend/.env.local
	@echo "wrote frontend/.env.local"

frontend-dev: frontend-env
	npm --prefix frontend run dev

frontend-build: frontend-env
	npm --prefix frontend run build

anvil:
	anvil
