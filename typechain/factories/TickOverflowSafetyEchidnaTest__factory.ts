/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import { Contract, ContractFactory, Overrides } from "@ethersproject/contracts";

import type { TickOverflowSafetyEchidnaTest } from "../TickOverflowSafetyEchidnaTest";

export class TickOverflowSafetyEchidnaTest__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(overrides?: Overrides): Promise<TickOverflowSafetyEchidnaTest> {
    return super.deploy(
      overrides || {}
    ) as Promise<TickOverflowSafetyEchidnaTest>;
  }
  getDeployTransaction(overrides?: Overrides): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  attach(address: string): TickOverflowSafetyEchidnaTest {
    return super.attach(address) as TickOverflowSafetyEchidnaTest;
  }
  connect(signer: Signer): TickOverflowSafetyEchidnaTest__factory {
    return super.connect(signer) as TickOverflowSafetyEchidnaTest__factory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): TickOverflowSafetyEchidnaTest {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as TickOverflowSafetyEchidnaTest;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "int24",
        name: "tickLower",
        type: "int24",
      },
      {
        internalType: "int24",
        name: "tickUpper",
        type: "int24",
      },
      {
        internalType: "int128",
        name: "liquidityDelta",
        type: "int128",
      },
    ],
    name: "getPosition",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseFeeGrowthGlobal0X128",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseFeeGrowthGlobal1X128",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "int24",
        name: "target",
        type: "int24",
      },
    ],
    name: "moveToTick",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "int24",
        name: "",
        type: "int24",
      },
    ],
    name: "ticks",
    outputs: [
      {
        internalType: "uint128",
        name: "liquidityGross",
        type: "uint128",
      },
      {
        internalType: "int128",
        name: "liquidityNet",
        type: "int128",
      },
      {
        internalType: "uint256",
        name: "feeGrowthOutside0X128",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "feeGrowthOutside1X128",
        type: "uint256",
      },
      {
        internalType: "int56",
        name: "tickCumulativeOutside",
        type: "int56",
      },
      {
        internalType: "uint160",
        name: "secondsPerLiquidityOutsideX128",
        type: "uint160",
      },
      {
        internalType: "uint32",
        name: "secondsOutside",
        type: "uint32",
      },
      {
        internalType: "bool",
        name: "initialized",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const _bytecode =
  "0x60806040526001805462ffffff19169055600060028190556001600160ff1b036003819055600455600581905560065534801561003b57600080fd5b5061096e8061004b6000396000f3fe608060405234801561001057600080fd5b50600436106100675760003560e01c80636705a1f1116100505780636705a1f114610094578063af759368146100a7578063f30dba93146100ba57610067565b80630b0c061f1461006c5780633f03e19414610081575b600080fd5b61007f61007a3660046108f1565b6100ea565b005b61007f61008f3660046108f1565b61010d565b61007f6100a23660046108a6565b610130565b61007f6100b5366004610885565b6102e8565b6100cd6100c8366004610885565b610415565b6040516100e1989796959493929190610909565b60405180910390f35b600554818101116100fa57600080fd5b6003805482019055600580549091019055565b6006548181011161011d57600080fd5b6004805482019055600680549091019055565b600f19600284900b1361014257600080fd5b6010600283900b1261015357600080fd5b8160020b8360020b1261016557600080fd5b6001546003546004546000926101a392879260029290920b918691908680428160206001600160801b035b60009a9998979695949392919004610483565b905060006101db84600160009054906101000a900460020b8560035460045460008042600060206001600160801b0380168161019057fe5b9050811561024a57600083600f0b121561022557600285810b900b6000908152602081905260409020546001600160801b03161561021557fe5b610220600086610676565b61024a565b600285810b900b6000908152602081905260409020546001600160801b031661024a57fe5b80156102b757600083600f0b121561029257600284810b900b6000908152602081905260409020546001600160801b03161561028257fe5b61028d600085610676565b6102b7565b600284810b900b6000908152602081905260409020546001600160801b03166102b757fe5b60028054600f85900b0190819055600013156102cf57fe5b6002546102e157600060058190556006555b5050505050565b600f19600282900b136102fa57600080fd5b6010600282900b1261030b57600080fd5b600154600282810b91810b900b1461041257600154600282810b91810b900b12156103a05760018054600290810b909101810b900b6000908152602081905260409020546001600160801b03161561037e576001805460035460045461037c9360009360020b0191908380426106a2565b505b60018054600281810b8301900b62ffffff1662ffffff1990911617905561040d565b600154600290810b810b900b6000908152602081905260409020546001600160801b0316156103ea576001546003546004546103e89260009260029190910b918380426106a2565b505b60018054600019600282810b91909101900b62ffffff1662ffffff199091161790555b61030b565b50565b60006020819052908152604090208054600182015460028301546003909301546001600160801b03831693600160801b909304600f0b9290600681900b9067010000000000000081046001600160a01b031690600160d81b810463ffffffff1690600160f81b900460ff1688565b60028a810b900b600090815260208c90526040812080546001600160801b0316826104ae828d610775565b9050846001600160801b0316816001600160801b031611156104fc576040805162461bcd60e51b81526020600482015260026024820152614c4f60f01b604482015290519081900360640190fd5b6001600160801b0382811615908216158114159450156105d2578c60020b8e60020b136105a257600183018b9055600283018a90556003830180547fffffffffff0000000000000000000000000000000000000000ffffffffffffff166701000000000000006001600160a01b038c16021766ffffffffffffff191666ffffffffffffff60068b900b161763ffffffff60d81b1916600160d81b63ffffffff8a16021790555b6003830180547effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff16600160f81b1790555b82546fffffffffffffffffffffffffffffffff19166001600160801b0382161783558561062457825461061f9061061a90600160801b9004600f90810b810b908f900b610831565b610847565b610645565b82546106459061061a90600160801b9004600f90810b810b908f900b61085d565b8354600f9190910b6001600160801b03908116600160801b0291161790925550909c9b505050505050505050505050565b600290810b810b6000908152602092909252604082208281556001810183905590810182905560030155565b600295860b860b60009081526020979097526040909620600181018054909503909455938301805490920390915560038201805463ffffffff600160d81b6001600160a01b036701000000000000008085048216909603169094027fffffffffff0000000000000000000000000000000000000000ffffffffffffff90921691909117600681810b90960390950b66ffffffffffffff1666ffffffffffffff199095169490941782810485169095039093160263ffffffff60d81b1990931692909217905554600160801b9004600f0b90565b60008082600f0b12156107da57826001600160801b03168260000384039150816001600160801b0316106107d5576040805162461bcd60e51b81526020600482015260026024820152614c5360f01b604482015290519081900360640190fd5b61082b565b826001600160801b03168284019150816001600160801b0316101561082b576040805162461bcd60e51b81526020600482015260026024820152614c4160f01b604482015290519081900360640190fd5b92915050565b8181018281121560008312151461082b57600080fd5b80600f81900b811461085857600080fd5b919050565b8082038281131560008312151461082b57600080fd5b8035600281900b811461085857600080fd5b600060208284031215610896578081fd5b61089f82610873565b9392505050565b6000806000606084860312156108ba578182fd5b6108c384610873565b92506108d160208501610873565b9150604084013580600f0b81146108e6578182fd5b809150509250925092565b600060208284031215610902578081fd5b5035919050565b6001600160801b03989098168852600f9690960b60208801526040870194909452606086019290925260060b60808501526001600160a01b031660a084015263ffffffff1660c0830152151560e0820152610100019056fea164736f6c6343000706000a";
