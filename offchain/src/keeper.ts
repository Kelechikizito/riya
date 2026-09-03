// Ethereum-only and optional: polls `AaveV4Adapter.yieldAccrued()`, calls the permissionless `harvest()`
// once it clears its own threshold, and so creates the `TokensHarvested` event the worker later proves.

// @question is this scalable? how does this work in production-grade software, where there has to be a monitoring service/tool
