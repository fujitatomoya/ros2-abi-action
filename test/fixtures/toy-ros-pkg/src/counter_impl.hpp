// Private header of the toy fixture: lives under src/, is never installed, and
// is therefore not part of the ABI. -DPRIVATE_CHANGE alters it in every way a
// pimpl refactor would: layout, a removed member function, an added one.
#pragma once

#include "toy/counter.hpp"

namespace toy
{

struct Counter::Impl
{
#ifdef PRIVATE_CHANGE
  long calls;
  long last;
  void record(int v);
#else
  int calls;
  void touch();
#endif
};

}  // namespace toy
