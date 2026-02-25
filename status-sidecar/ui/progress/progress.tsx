import * as React from 'react';
import * as ProgressPrimitive from '@radix-ui/react-progress';
import { cva, type VariantProps } from 'class-variance-authority';
import { Loader2, CheckCircle, AlertCircle, PauseCircle } from 'lucide-react';

import { cn } from '@/lib/utils';

const progressVariants = cva('', {
  variants: {
    state: {
      'in-progress': '',
      success: '',
      error: '',
      paused: '',
      infinite: '',
    },
  },
  defaultVariants: {
    state: 'in-progress',
  },
});

// State-specific Tailwind class configuration matching Figma tokens
const stateClasses = {
  'in-progress': {
    foreground: 'bg-primary',
    background: 'bg-background-medium',
    icon: 'text-primary',
    label: 'text-text-dark',
  },
  success: {
    foreground: 'bg-success',
    background: 'bg-transparent',
    icon: 'text-success',
    label: 'text-text-dark',
  },
  error: {
    foreground: 'bg-error',
    background: 'bg-background-medium',
    icon: 'text-error',
    label: 'text-text-dark',
  },
  paused: {
    foreground: 'bg-warning',
    background: 'bg-background-medium',
    icon: 'text-warning',
    label: 'text-text-dark',
  },
  infinite: {
    foreground: 'bg-primary',
    background: 'bg-primary-transparent',
    icon: 'text-primary',
    label: 'text-text-dark',
  },
} as const;

// State-specific icons
const stateIcons = {
  'in-progress': Loader2,
  success: CheckCircle,
  error: AlertCircle,
  paused: PauseCircle,
  infinite: Loader2,
} as const;

// State-specific labels
const stateLabels = {
  'in-progress': 'In Progress',
  success: 'Success',
  error: 'Error Message',
  paused: 'Paused',
  infinite: 'In Progress',
} as const;

export interface ProgressProps
  extends
    Omit<
      React.ComponentPropsWithoutRef<typeof ProgressPrimitive.Root>,
      'children'
    >,
    VariantProps<typeof progressVariants> {
  /**
   * The state of the progress bar
   * @default "in-progress"
   */
  state?: 'in-progress' | 'success' | 'error' | 'paused' | 'infinite';

  /**
   * Custom status label (overrides default state label)
   */
  statusLabel?: string;

  /**
   * Whether to show the status icon and label
   * @default true
   */
  showStatus?: boolean;

  /**
   * Whether to show the percentage text
   * @default true
   */
  showPercentage?: boolean;

  /**
   * Whether to animate the icon (applies to in-progress and infinite states)
   * @default true
   */
  animateIcon?: boolean;
}

const Progress = React.forwardRef<
  React.ElementRef<typeof ProgressPrimitive.Root>,
  ProgressProps
>(
  (
    {
      className,
      value,
      state = 'in-progress',
      statusLabel,
      showStatus = true,
      showPercentage = true,
      animateIcon = true,
      ...props
    },
    ref
  ) => {
    const classes = stateClasses[state];
    const IconComponent = stateIcons[state];
    const defaultLabel = stateLabels[state];
    const label = statusLabel ?? defaultLabel;

    // For infinite state, value is not shown
    const isInfinite = state === 'infinite';

    // Clamp value to valid range (0 to max, or 0 to 100 if max not specified)
    const max = props.max ?? 100;
    const clampedValue = React.useMemo(() => {
      if (isInfinite || value === null || value === undefined) {
        return undefined;
      }
      // Clamp between 0 and max
      return Math.max(0, Math.min(value, max));
    }, [value, max, isInfinite]);

    const displayValue = clampedValue ?? 0;
    const shouldShowPercentage =
      showPercentage && !isInfinite && state !== 'success';

    return (
      <div className="flex w-full flex-col gap-1">
        {/* Title section with status and percentage */}
        <div className="flex w-full items-center justify-between">
          {/* Left: Status icon + label */}
          {showStatus && (
            <div className="flex h-5 shrink-0 items-center gap-1">
              <IconComponent
                className={cn(
                  'size-4 shrink-0',
                  classes.icon,
                  animateIcon &&
                    (state === 'in-progress' || state === 'infinite') &&
                    'animate-spin'
                )}
                strokeWidth={1.5}
                aria-hidden="true"
              />
              <span
                className={cn(
                  'font-sans text-base leading-5 font-normal whitespace-nowrap',
                  classes.label
                )}
              >
                {label}
              </span>
            </div>
          )}

          {/* Right: Percentage text */}
          {shouldShowPercentage && (
            <span
              className={cn(
                'shrink-0 font-sans text-base leading-5 font-semibold whitespace-nowrap',
                classes.label
              )}
            >
              {Math.round(displayValue ?? 0)}%
            </span>
          )}
        </div>

        {/* Progress bar */}
        <div className="relative w-full">
          <ProgressPrimitive.Root
            ref={ref}
            className={cn(
              'rounded-2xs relative h-[4px] w-full overflow-hidden',
              classes.background,
              progressVariants({ state }),
              className
            )}
            value={clampedValue}
            {...props}
          >
            <ProgressPrimitive.Indicator
              className={cn(
                'rounded-2xs h-full w-full flex-1 transition-transform duration-300 ease-in-out',
                classes.foreground,
                isInfinite && 'animate-progress-infinite'
              )}
              style={{
                transform: isInfinite
                  ? 'translateX(-50%)'
                  : `translateX(-${100 - displayValue}%)`,
              }}
            />
          </ProgressPrimitive.Root>
        </div>
      </div>
    );
  }
);

Progress.displayName = 'Progress';

export { Progress };
// eslint-disable-next-line react-refresh/only-export-components
export { progressVariants };
