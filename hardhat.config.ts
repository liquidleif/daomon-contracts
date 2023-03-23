import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.18",
        settings: {
            optimizer: {
                enabled: true,
                runs: 1000,
            },
        },
    },
    gasReporter: {
        currency: "USD",
        gasPrice: 100,
        enabled: true, // set to false to disable the reporter
        coinmarketcap: "", // add your API key here
        maxMethodDiff: 10,
    },
};

export default config;
