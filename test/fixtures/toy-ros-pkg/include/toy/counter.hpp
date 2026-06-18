// Toy public header for ros2-abi-action self-tests.
//
// A single header/source compiles three ways via preprocessor macros so the CI
// self-test can produce a baseline plus two deltas without separate files:
//
//   (default)      baseline ABI
//   -DADD_SYMBOL   adds a new exported method  -> additions-only (safe)
//   -DBREAK_ABI    changes object layout + a   -> incompatible (break)
//                  function signature
//
#pragma once

namespace toy
{

/// A trivial counter whose ABI we diff across builds.
class Counter
{
public:
  Counter();
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
