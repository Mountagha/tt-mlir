add_custom_target(MLIRUnitTests)
set_target_properties(MLIRUnitTests PROPERTIES FOLDER "MLIR Tests")

function(add_mlir_unittest test_dirname)
  add_unittest(MLIRUnitTests ${test_dirname} ${ARGN})
endfunction()

add_subdirectory(Allocation)
add_subdirectory(Support)
add_subdirectory(TestScheduler)
add_subdirectory(Optimizer)
add_subdirectory(OpModel)
add_subdirectory(TTNNToEmitC)
