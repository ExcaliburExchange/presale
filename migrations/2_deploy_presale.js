const Presale = artifacts.require('Presale');

const FACTORY_ADDRESS = process.env.FACTORY_ADDRESS.toString().trim();
const WETH_ADDRESS = process.env.WETH_ADDRESS.toString().trim();
const EXC_ADDRESS = process.env.EXC_ADDRESS.toString().trim();
const DIVIDENDS_ADDRESS = process.env.DIVIDENDS_ADDRESS.toString().trim();
const PRESALE_START_TIME = process.env.PRESALE_START_TIME;
const PRESALE_END_TIME = process.env.PRESALE_END_TIME;

module.exports = async function (deployer) {
  await deployer.deploy(Presale, EXC_ADDRESS, WETH_ADDRESS, FACTORY_ADDRESS, DIVIDENDS_ADDRESS, PRESALE_START_TIME, PRESALE_END_TIME);
};
