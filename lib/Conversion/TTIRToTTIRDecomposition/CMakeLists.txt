add_mlir_conversion_library(TTMLIRTTIRToTTIRDecomposition
  TTIRToTTIRDecomposition.cpp
  TTIRToTTIRDecompositionPass.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/ttmlir/Conversion/TTIRToTTIR

  DEPENDS
  TTMLIRConversionPassIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
)
