const {BN} = require("@openzeppelin/test-helpers");

async function increaseTo(contract, timestamp) {
  await contract.setCurrentBlockTimestamp(timestamp);
}

async function increase(contract, seconds) {
  await contract.setCurrentBlockTimestamp((await contract.currentBlockTimestamp()).add(new BN(seconds)));
}

async function latest(contract) {
  return await contract.currentBlockTimestamp();
}

module.exports = {
  increaseTo,
  increase,
  latest
}