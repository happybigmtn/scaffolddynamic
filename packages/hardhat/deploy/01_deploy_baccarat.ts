import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployContracts: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  // Deploy FreeChips
  const freeChips = await deploy("Chips", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [deployer],
      },
    },
  });

  console.log("FreeChips deployed to:", freeChips.address);

  // Deploy BaccaratGame
  const baccaratGame = await deploy("BaccaratGame", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [freeChips.address],
      },
    },
  });

  console.log("BaccaratGame deployed to:", baccaratGame.address);
};

export default deployContracts;
deployContracts.tags = ["FreeChips", "BaccaratGame"];
