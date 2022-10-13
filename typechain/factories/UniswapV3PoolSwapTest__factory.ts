/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import { Contract, ContractFactory, Overrides } from "@ethersproject/contracts";

import type { UniswapV3PoolSwapTest } from "../UniswapV3PoolSwapTest";

export class UniswapV3PoolSwapTest__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(overrides?: Overrides): Promise<UniswapV3PoolSwapTest> {
    return super.deploy(overrides || {}) as Promise<UniswapV3PoolSwapTest>;
  }
  getDeployTransaction(overrides?: Overrides): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  attach(address: string): UniswapV3PoolSwapTest {
    return super.attach(address) as UniswapV3PoolSwapTest;
  }
  connect(signer: Signer): UniswapV3PoolSwapTest__factory {
    return super.connect(signer) as UniswapV3PoolSwapTest__factory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): UniswapV3PoolSwapTest {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as UniswapV3PoolSwapTest;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "pool",
        type: "address",
      },
      {
        internalType: "bool",
        name: "zeroForOne",
        type: "bool",
      },
      {
        internalType: "int256",
        name: "amountSpecified",
        type: "int256",
      },
      {
        internalType: "uint160",
        name: "sqrtPriceLimitX96",
        type: "uint160",
      },
    ],
    name: "getSwapResult",
    outputs: [
      {
        internalType: "int256",
        name: "amount0Delta",
        type: "int256",
      },
      {
        internalType: "int256",
        name: "amount1Delta",
        type: "int256",
      },
      {
        internalType: "uint160",
        name: "nextSqrtRatio",
        type: "uint160",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "int256",
        name: "amount0Delta",
        type: "int256",
      },
      {
        internalType: "int256",
        name: "amount1Delta",
        type: "int256",
      },
      {
        internalType: "bytes",
        name: "data",
        type: "bytes",
      },
    ],
    name: "uniswapV3SwapCallback",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b506104f9806100206000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c80637f2ba7bc1461003b578063fa461e331461009e575b600080fd5b6100776004803603608081101561005157600080fd5b506001600160a01b0381358116916020810135151591604082013591606001351661011c565b6040805193845260208401929092526001600160a01b031682820152519081900360600190f35b61011a600480360360608110156100b457600080fd5b8135916020810135918101906060810160408201356401000000008111156100db57600080fd5b8201836020820111156100ed57600080fd5b8035906020019184600183028401116401000000008311171561010f57600080fd5b5090925090506102d9565b005b6000806000866001600160a01b031663128acb0860008888883360405160200180826001600160a01b031681526020019150506040516020818303038152906040526040518663ffffffff1660e01b815260040180866001600160a01b031681526020018515158152602001848152602001836001600160a01b0316815260200180602001828103825283818151815260200191508051906020019080838360005b838110156101d65781810151838201526020016101be565b50505050905090810190601f1680156102035780820380516001836020036101000a031916815260200191505b5096505050505050506040805180830381600087803b15801561022557600080fd5b505af1158015610239573d6000803e3d6000fd5b505050506040513d604081101561024f57600080fd5b50805160209091015160408051633850c7bd60e01b815290519295509093506001600160a01b03891691633850c7bd9160048082019260e092909190829003018186803b15801561029f57600080fd5b505afa1580156102b3573d6000803e3d6000fd5b505050506040513d60e08110156102c957600080fd5b5051929791965091945092505050565b6000828260208110156102eb57600080fd5b50356001600160a01b0316905060008513156103f157336001600160a01b0316630dfe16816040518163ffffffff1660e01b815260040160206040518083038186803b15801561033a57600080fd5b505afa15801561034e573d6000803e3d6000fd5b505050506040513d602081101561036457600080fd5b5051604080516323b872dd60e01b81526001600160a01b03848116600483015233602483015260448201899052915191909216916323b872dd9160648083019260209291908290030181600087803b1580156103bf57600080fd5b505af11580156103d3573d6000803e3d6000fd5b505050506040513d60208110156103e957600080fd5b506104e59050565b60008413156104e557336001600160a01b031663d21220a76040518163ffffffff1660e01b815260040160206040518083038186803b15801561043357600080fd5b505afa158015610447573d6000803e3d6000fd5b505050506040513d602081101561045d57600080fd5b5051604080516323b872dd60e01b81526001600160a01b03848116600483015233602483015260448201889052915191909216916323b872dd9160648083019260209291908290030181600087803b1580156104b857600080fd5b505af11580156104cc573d6000803e3d6000fd5b505050506040513d60208110156104e257600080fd5b50505b505050505056fea164736f6c6343000706000a";
