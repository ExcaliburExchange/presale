const HDWalletProvider = require('@truffle/hdwallet-provider');
require('dotenv').config();

const MNENOMIC = process.env.MNEMONIC.toString().trim();

module.exports = {
  networks: {
    development: {
      host: '127.0.0.1', // Localhost (default: none)
      port: 8545, // Standard BSC port (default: none)
      network_id: '*', // Any network (default: none)
    },
    ftmTestnet: {
      provider: () => new HDWalletProvider(MNENOMIC, 'https://xapi.testnet.fantom.network/lachesis'),
      network_id: "4002",
      timeoutBlocks: 1200,
      skipDryRun: true,
      from: process.env.DEPLOYER_ADDRESS.toString().trim(),
    },
  },

  plugins: [
    'truffle-plugin-verify',
  ],

  // Configure your compilers
  compilers: {
    solc: {
      // https://forum.openzeppelin.com/t/how-to-deploy-uniswapv2-on-ganache/3885
      version: '0.7.6', // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
      settings: { // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 999999,
        },
      },
    },
  },

  mocha: {
    reporter: 'eth-gas-reporter',
    reporterOptions: {
      currency: 'USD',
    },
  },
};
