import { type VariantProps } from 'class-variance-authority';
import * as React from 'react';
import { cn } from '@/lib/utils';
import { H5 } from '@/ui/typography';
import { segmentVariants } from './segment.variants';

// Props interface matching Figma properties EXACTLY
export interface SegmentProps
  extends
    React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof segmentVariants> {
  // Figma property (lowercase prop name from Figma property name)
  state?: 'default' | 'hover' | 'active' | 'disabled'; // Figma: "State"

  // Additional props not in Figma
  selected?: boolean; // For use in SegmentedButton groups
}

const Segment = React.forwardRef<HTMLButtonElement, SegmentProps>(
  (
    {
      className,
      state = 'default', // Figma default
      selected = false,
      disabled = false,
      children,
      ...props
    },
    ref
  ) => {
    // Determine effective state based on props
    const effectiveState = disabled ? 'disabled' : selected ? 'active' : state;

    return (
      <button
        ref={ref}
        type="button"
        disabled={disabled}
        className={cn(segmentVariants({ state: effectiveState }), className)}
        aria-pressed={selected}
        {...props}
      >
        <H5>{children}</H5>
      </button>
    );
  }
);
Segment.displayName = 'Segment';

export { Segment };
