import { cva } from 'class-variance-authority';

/**
 * Tooltip variants
 *
 * Note: Tooltip positioning is handled by Radix UI's `side` and `align` props,
 * not by CVA variants. This file exists for consistency with other components.
 *
 * Positioning props:
 * - side: "top" | "right" | "bottom" | "left"
 * - align: "start" | "center" | "end"
 *
 * Example usage:
 * <TooltipContent side="top" align="center">...</TooltipContent>
 */
export const tooltipVariants = cva(
  'z-50 overflow-hidden rounded-xs bg-background px-2 py-2 text-sm text-text-medium shadow-xs',
  {
    variants: {},
    defaultVariants: {},
  }
);
