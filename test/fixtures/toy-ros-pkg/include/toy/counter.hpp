// Toy public header for ros2-abi-action self-tests.
//
// A single header/source compiles three ways via preprocessor macros so the CI
// self-test can produce a baseline plus two deltas without separate files:
//
//   (default)         baseline ABI
//   -DADD_SYMBOL      adds a new exported method  -> additions-only (safe)
//   -DBREAK_ABI       changes object layout + a   -> incompatible (break)
//                     function signature
//   -DPRIVATE_CHANGE  changes the pimpl class in   -> compatible: src/ is not
//                     src/counter_impl.hpp           installed, so not ABI
//
#pragma once

#include <memory>

namespace toy
{

/// A trivial counter whose ABI we diff across builds.
class Counter
{
public:
  Counter();
  ~Counter();
  int value() const;
  void increment();
#ifdef ADD_SYMBOL
  /// New backward-compatible method (additions-only).
  void decrement();
#endif

private:
  int count_;
#ifdef BREAK_ABI
  // Extra member changes the object layout -> ABI break.
  long extra_;
#endif
  // Opaque state defined in src/counter_impl.hpp (pimpl): its layout and
  // member functions are implementation, not ABI.
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

/// Free function whose signature changes under -DBREAK_ABI (mangled symbol
/// changes -> removed/added symbol -> ABI break).
int compute(
  int a
#ifdef BREAK_ABI
  , int b
#endif
);

}  // namespace toy
