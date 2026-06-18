#include "toy/counter.hpp"

namespace toy
{

Counter::Counter()
: count_(0)
#ifdef BREAK_ABI
  , extra_(0)
#endif
{
}

int Counter::value() const
{
  return count_;
}

void Counter::increment()
{
  ++count_;
}

#ifdef ADD_SYMBOL
void Counter::decrement()
{
  --count_;
}
#endif

int compute(
  int a
#ifdef BREAK_ABI
  , int b
#endif
)
{
  return a
#ifdef BREAK_ABI
    + b
#endif
  ;
}

}  // namespace toy
