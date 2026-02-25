import * as React from 'react';
import { cn } from '@/lib/utils';

export interface DividerProps extends React.HTMLAttributes<HTMLDivElement> {
  /**
   * Orientation of the divider
   * @default "horizontal"
   */
  orientation?: 'horizontal' | 'vertical';

  /**
   * Visual variant for different backgrounds
   * - "default": Uses border-light for light backgrounds
   * - "dark": Uses theme-medium for dark/theme backgrounds (navigation, sidebars)
   * @default "default"
   */
  variant?: 'default' | 'dark';
}

/**
 * Divider Component
 *
 * A visual separator for dividing content. Use between navigation items,
 * accordion sections, or any content that needs visual separation.
 *
 * @example
 * ```tsx
 * // Horizontal divider (default)
 * <Divider />
 *
 * // Vertical divider
 * <Divider orientation="vertical" />
 *
 * // Dark variant for navigation/themed backgrounds
 * <Divider variant="dark" />
 * ```
 */
export const Divider = React.forwardRef<HTMLDivElement, DividerProps>(
  (
    { className, orientation = 'horizontal', variant = 'default', ...props },
    ref
  ) => {
    return (
      <div
        ref={ref}
        role="separator"
        aria-orientation={orientation}
        className={cn(
          'rounded-2xs shrink-0',
          orientation === 'horizontal' && 'h-px w-full',
          orientation === 'vertical' && 'h-full w-px',
          variant === 'default' && 'bg-border-light',
          variant === 'dark' && 'bg-theme-medium',
          className
        )}
        {...props}
      />
    );
  }
);

Divider.displayName = 'Divider';
