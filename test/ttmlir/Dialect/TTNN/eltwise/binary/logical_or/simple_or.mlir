// RUN: ttmlir-opt --ttir-to-ttnn-backend-pipeline %s | FileCheck %s
module attributes {} {
  func.func @logical_or(%arg0: tensor<64x128xf32>, %arg1: tensor<64x128xf32>) -> tensor<64x128xf32> {
    %0 = ttir.empty() : tensor<64x128xf32>
    %1 = "ttir.logical_or"(%arg0, %arg1, %0) : (tensor<64x128xf32>, tensor<64x128xf32>, tensor<64x128xf32>) -> tensor<64x128xf32>
    // CHECK: "ttnn.logical_or"
    // CHECK-SAME: tensor<64x128xf32
    // CHECK-SAME: tensor<64x128xf32
    // CHECK-SAME: -> tensor<64x128xf32
    return %1 : tensor<64x128xf32>
  }
}
