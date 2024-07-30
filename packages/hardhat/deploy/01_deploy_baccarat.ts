import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";

/**
 * Deploys FreeChips and BaccaratGame contracts using the deployer account
 *
 * @param hre HardhatRuntimeEnvironment object.
 */
const deployBaccaratContracts: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  // Deploy FreeChips
  const freeChips = await deploy("FreeChips", {
    from: deployer,
    args: [],
    log: true,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [deployer],
      },
    },
    autoMine: true,
  });

  // Deploy BaccaratGame
  await deploy("BaccaratGame", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  });

  // Get the deployed BaccaratGame contract to interact with it after deploying
  const baccaratGameContract = await hre.ethers.getContract<Contract>("BaccaratGame", deployer);

  // Initialize BaccaratGame
  console.log("Initializing BaccaratGame contract...");
  const baccaratInitTx = await baccaratGameContract.initialize(freeChips.address);
  await baccaratInitTx.wait();
  console.log("BaccaratGame contract initialized");
};

export default deployBaccaratContracts;

// Tags are useful if you have multiple deploy files and only want to run one of them.
// e.g. yarn deploy --tags FreeChips,BaccaratGame
deployBaccaratContracts.tags = ["FreeChips", "BaccaratGame"];
