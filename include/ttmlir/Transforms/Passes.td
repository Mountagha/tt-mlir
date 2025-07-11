// SPDX-FileCopyrightText: (c) 2025 Tenstorrent AI ULC
//
// SPDX-License-Identifier: Apache-2.0

#ifndef TTMLIR_TRANSFORMS_PASSES_TD
#define TTMLIR_TRANSFORMS_PASSES_TD

include "mlir/Pass/PassBase.td"

def ConstEvalHoistTransform: Pass<"const-eval-hoist-transform", "::mlir::ModuleOp"> {
  let summary = "Transform to hoist const-eval subgraph into separate func(s)";
  let description = [{
    Transform pass which runs an analysis pass to find const-eval subgraphs in an input
    and hoist them into separate functions.
    This pass is dialect-agnostic, although ops with TT traits TTCoreCreationOpTrait and TTCoreDuplicateConstEvalTrait have special logic.
    If this pass is run on IR which has already been const-eval'ed, it will first undo existing const-eval hoisting and then re-run.

    Example:

    func.func @forward(%arg0: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<input>}, %arg1: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<parameter>}, %arg2: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<parameter>}, %arg3: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<constant>}) -> tensor<32x32xbf16> {
      %0 = tensor.empty() : tensor<32x32xbf16>
      %1 = "ttir.add"(%arg0, %arg1, %0) : (tensor<32x32xbf16>, tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      %2 = tensor.empty() : tensor<32x32xbf16>
      %3 = "ttir.subtract"(%arg2, %arg3, %2) : (tensor<32x32xbf16>, tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      %4 = tensor.empty() : tensor<32x32xbf16>
      %5 = "ttir.add"(%1, %3, %4) : (tensor<32x32xbf16>, tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      return %5 : tensor<32x32xbf16>
    }

    becomes:

    func.func @forward(%arg0: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<input>}, %arg1: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<parameter>}, %arg2: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<parameter>}, %arg3: tensor<32x32xbf16> {ttcore.argument_type = #ttcore.argument_type<constant>}) -> tensor<32x32xbf16> {
      %0 = ttcore.load_cached(@forward_const_eval_0, [%arg2, %arg3]) : (tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      %1 = tensor.empty() : tensor<32x32xbf16>
      %2 = "ttir.add"(%arg0, %arg1, %1) : (tensor<32x32xbf16>, tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      %3 = tensor.empty() : tensor<32x32xbf16>
      %4 = "ttir.add"(%2, %0, %3) : (tensor<32x32xbf16>, tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      return %4 : tensor<32x32xbf16>
    }
    func.func @forward_const_eval_0(%arg0: tensor<32x32xbf16>, %arg1: tensor<32x32xbf16>) -> tensor<32x32xbf16> attributes {const_eval} {
      %0 = tensor.empty() : tensor<32x32xbf16>
      %1 = "ttir.subtract"(%arg0, %arg1, %0) : (tensor<32x32xbf16>, tensor<32x32xbf16>, tensor<32x32xbf16>) -> tensor<32x32xbf16>
      return %1 : tensor<32x32xbf16>
    }

  }];

  let dependentDialects = ["::mlir::tt::ttcore::TTCoreDialect"];
}

def UndoConstEvalTransform : Pass<"undo-const-eval", "mlir::ModuleOp"> {
  let summary = "Undo const-eval hoisting by inlining const-eval functions";
  let description = [{
    This pass inlines all functions marked with the "const_eval" attribute,
    effectively undoing the transformations performed by ConstEvalHoistTransform.
  }];

  let dependentDialects = ["::mlir::tt::ttcore::TTCoreDialect"];
}

def ReenableLostDPS: Pass<"ttir-reenable-dps", "::mlir::ModuleOp"> {
  let summary = "Transform functions with return values to use output parameters.";
  let description = [{
    This pass finds functions with the ttir.return_to_output_mapping attribute and
    transforms them to use output parameters instead of return values. This is useful
    for operations that implement the DestinationStyleOpInterface, where we want to
    write directly to the output buffer instead of creating a new tensor and returning it.

    Example:
    ```mlir
    // Before
    func.func @hoisted_op(%arg0: tensor<4x4xf32>, %arg1: tensor<4x4xf32>) -> tensor<4x4xf32> {
      %0 = linalg.generic ... {
        ...
      } : tensor<4x4xf32>, tensor<4x4xf32> -> tensor<4x4xf32>
      return %0 : tensor<4x4xf32>
    }

    // After
    func.func @hoisted_op(%arg0: tensor<4x4xf32>, %arg1: tensor<4x4xf32>, %arg2: tensor<4x4xf32>) {
      // The linalg.generic now writes directly to %arg2 instead of creating a new tensor
      linalg.generic ... {
        ...
      } : tensor<4x4xf32>, tensor<4x4xf32>, tensor<4x4xf32>
      return
    }
    ```
  }];

  let dependentDialects = ["mlir::linalg::LinalgDialect", "mlir::tensor::TensorDialect", "mlir::func::FuncDialect"];
}

def RemoveReturnValues: Pass<"ttir-remove-return-values", "::mlir::ModuleOp"> {
  let summary = "Remove return values from functions.";
  let description = [{
    This pass finds functions with return values and transforms them to have no return
    values.  We use this on the CPU hoisting path, since we want to avoid RVO issues at
    runtime, but model the functions as returning values during some intermediate stages
    to avoid op elimination, track which operation is the final output (corresponding
    to DPS output tensor), etc.

    Example:
    ```mlir
    // Before
    func.func @hoisted_op(%arg0: tensor<4x4xf32>, %arg1: tensor<4x4xf32>) -> tensor<4x4xf32> {
      %0 = linalg.generic ... {
        ...
      } : tensor<4x4xf32>, tensor<4x4xf32> -> tensor<4x4xf32>
      return %0 : tensor<4x4xf32>
    }

    // After
    func.func @hoisted_op(%arg0: tensor<4x4xf32>, %arg1: tensor<4x4xf32>) {
      %0 = linalg.generic ... {
        ...
      } : tensor<4x4xf32>, tensor<4x4xf32> -> tensor<4x4xf32>
      return
    }
    ```
  }];

  let dependentDialects = ["mlir::func::FuncDialect"];
}

#endif
