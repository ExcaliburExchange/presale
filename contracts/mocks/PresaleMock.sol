// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "../Presale.sol";

// Mock class using Presale
// Allows to test Presale with a precise block.timestamp
contract PresaleMock is Presale {
  using SafeMath for uint256;
  uint256 public currentBlockTimestamp = 1;

  constructor(
    address exc_,
    address wftm_,
    IExcaliburV2Factory factory_,
    IDividends dividends_,
    uint256 startTime_,
    uint256 endTime_
  ) Presale(exc_, wftm_, factory_, dividends_, startTime_, endTime_) {}

  function buildLP() external onlyOwner virtual override {
    isLpBuilt = true;
    lpToClaim = WFTM;
    totalLPAmountToClaim = totalAllocation.div(10);
  }

  function setCurrentBlockTimestamp(uint256 timestamp) external {
    currentBlockTimestamp = timestamp;
  }

  function _currentBlockTimestamp() internal view override returns (uint256) {
    return currentBlockTimestamp;
  }
}
