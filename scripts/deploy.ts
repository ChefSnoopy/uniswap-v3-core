import { ethers, network } from "hardhat";
import config from "../config";
import {parseEther} from "ethers/lib/utils";

const currentNetwork = network.name;

const main = async () => {
    console.log("Deploying to network:", currentNetwork);

    const ContractObj = await ethers.getContractFactory("IFODeployerV5");
    const obj = await ContractObj.deploy(
        '0xDf4dBf6536201370F95e06A0F8a7a70fE40E388a' // pancakeProfile
    );

    await obj.deployed();
    console.log("Contract deployed to:", obj.address);
};
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
