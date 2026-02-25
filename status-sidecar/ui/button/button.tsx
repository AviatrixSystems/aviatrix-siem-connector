import { Slot } from '@radix-ui/react-slot';
import { type VariantProps } from 'class-variance-authority';
import { Loader2 } from 'lucide-react';
import * as React from 'react';

import { cn } from '@/lib/utils';
import { buttonVariants } from './button.variants';

export interface ButtonProps
  extends
    React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  loading?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      intent,
      size,
      attention,
      asChild = false,
      leftIcon,
      rightIcon,
      loading = false,
      disabled,
      children,
      ...props
    },
    ref
  ) => {
    const Comp = asChild ? Slot : 'button';
    const ariaBusy = loading ? true : undefined;
    const ariaLive = loading ? 'polite' : undefined;

    return (
      <Comp
        className={cn(
          buttonVariants({ intent, size, attention, loading, className })
        )}
        ref={ref}
        disabled={disabled || loading}
        aria-busy={ariaBusy}
        aria-live={ariaLive}
        {...props}
      >
        <span className={cn('inline-flex items-center gap-1')}>
          {loading ? (
            <Loader2 size={16} className="animate-spin" aria-hidden="true" />
          ) : (
            leftIcon && (
              <span className="inline-flex items-center" aria-hidden="true">
                {leftIcon}
              </span>
            )
          )}
          {children}
          {!loading && rightIcon && (
            <span className="ml-2 inline-flex items-center" aria-hidden="true">
              {rightIcon}
            </span>
          )}
        </span>
      </Comp>
    );
  }
);
Button.displayName = 'Button';

export { Button };
