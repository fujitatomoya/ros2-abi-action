#include "counter_impl.hpp"

namespace toy
{

#ifdef PRIVATE_CHANGE
void Counter::Impl::record(int v)
{
  ++calls;
  last = v;
}
#else
void Counter::Impl::touch()
{
  ++calls;
}
#endif

Counter::Counter()
: count_(0),
#ifdef BREAK_ABI
  extra_(0),
#endif
  impl_(new Impl{})
{
}

Counter::~Counter() = default;

int Counter::value() const
{
  return count_;
}

void Counter::increment()
{
  ++count_;
#ifdef PRIVATE_CHANGE
  impl_->record(count_);
#else
  impl_->touch();
#endif
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
