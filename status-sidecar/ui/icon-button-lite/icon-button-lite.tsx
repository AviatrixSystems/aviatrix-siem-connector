import { Slot } from '@radix-ui/react-slot';
import { type VariantProps } from 'class-variance-authority';
import * as React from 'react';
import { cn } from '@/lib/utils';
import { iconButtonLiteVariants } from './icon-button-lite.variants';

/**
 * IconButtonLite Props
 *
 * Props interface matching Figma properties exactly (1:1 mapping).
 * This is a minimal icon-only button with subtle hover/pressed/disabled states.
 *
 * Figma: https://www.figma.com/design/floUsFzaaTXQeI0aNygqj9/Essential-Components?node-id=129-1571
 */
export interface IconButtonLiteProps
  extends
    React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof iconButtonLiteVariants> {
  /**
   * Button size
   * @figma "Size" property
   * @default "lg"
   */
  size?: 'lg' | 'md' | 'sm';

  /**
   * Visual state (for story/display purposes - actual states managed via HTML button states)
   * @figma "State" property
   * @default undefined
   */
  state?: 'default' | 'hover' | 'pressed' | 'disabled';

  /**
   * Icon element to display (use lucide-react icons)
   * @example <IconButtonLite icon={<X />} />
   */
  icon?: React.ReactNode;

  /**
   * Render as a child component (e.g., Link)
   * @default false
   */
  asChild?: boolean;
}

/**
 * IconButtonLite Component
 *
 * Minimal icon-only button with subtle color-only state changes (no backgrounds).
 * Designed for ultra-compact interfaces, toolbars, and inline actions where
 * maximum space efficiency is needed.
 *
 * Key differences from IconButtonAction:
 * - No background colors (transparent in all states)
 * - Smaller minimum size (SM = 12px)
 * - Only icon color changes on interaction
 * - More subtle visual feedback
 *
 * @example
 * ```tsx
 * import { X, Settings, ChevronRight, Plus } from 'lucide-react';
 * import { IconButtonLite } from '@/ui/icon-button-lite';
 *
 * // Basic usage
 * <IconButtonLite icon={<X />} aria-label="Close" />
 *
 * // Different sizes
 * <IconButtonLite icon={<Settings />} size="md" aria-label="Settings" />
 * <IconButtonLite icon={<Plus />} size="sm" aria-label="Add" />
 *
 * // Disabled state
 * <IconButtonLite icon={<ChevronRight />} disabled aria-label="Next" />
 *
 * // As Link (using asChild)
 * <IconButtonLite asChild icon={<Settings />}>
 *   <Link href="/settings" aria-label="Settings" />
 * </IconButtonLite>
 * ```
 */
const IconButtonLite = React.forwardRef<HTMLButtonElement, IconButtonLiteProps>(
  (
    {
      className,
      size = 'lg',
      state,
      icon,
      asChild = false,
      disabled,
      children,
      ...props
    },
    ref
  ) => {
    const Comp = asChild ? Slot : 'button';

    // Determine effective state for styling
    // Priority: disabled > state prop > default behavior
    const effectiveState = disabled ? 'disabled' : state || 'default';

    return (
      <Comp
        ref={ref}
        className={cn(
          iconButtonLiteVariants({ size, state: effectiveState }),
          className
        )}
        disabled={disabled}
        {...props}
      >
        {asChild ? (
          children
        ) : (
          <span className="flex items-center justify-center">
            {icon || children}
          </span>
        )}
      </Comp>
    );
  }
);

IconButtonLite.displayName = 'IconButtonLite';

export { IconButtonLite };
