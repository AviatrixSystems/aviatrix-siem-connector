import { cva } from 'class-variance-authority';

/**
 * IconButtonLite Variants
 *
 * CVA variant definitions matching Figma properties exactly.
 * Lite styling: transparent background, color-only state changes.
 *
 * Figma: https://www.figma.com/design/floUsFzaaTXQeI0aNygqj9/Essential-Components?node-id=129-1571
 */
export const iconButtonLiteVariants = cva(
  // Base classes - minimal button styling
  [
    'inline-flex',
    'items-center',
    'justify-center',
    'rounded-xs',
    'transition-colors',
    'focus-visible:outline-none',
    'focus-visible:ring-2',
    'focus-visible:ring-ring',
    'focus-visible:ring-offset-2',
    'disabled:pointer-events-none',
  ],
  {
    variants: {
      // Figma "Size" property
      size: {
        lg: [
          'size-8', // 32px × 32px (var(--element-LG))
          'p-2', // 8px padding (var(--padding-SM))
          '[&_svg]:size-4', // 16px icon (var(--icon-MD))
        ],
        md: [
          'size-6', // 24px × 24px (var(--element-MD))
          'p-1', // 4px padding (var(--padding-XS))
          '[&_svg]:size-4', // 16px icon (var(--icon-MD))
        ],
        sm: [
          'size-3', // 12px × 12px (var(--element-2XS))
          'p-0', // No padding
          '[&_svg]:size-3', // 12px icon (var(--icon-SM))
        ],
      },

      // Figma "State" property
      state: {
        default: [
          'text-text-medium', // rgba(98, 95, 104, 1) - Figma var: Text/Medium
          'hover:text-primary-medium', // Hover interaction
        ],
        hover: [
          'text-primary-medium', // rgba(4, 77, 149, 1) - Figma var: Primary/Medium
        ],
        pressed: [
          'text-primary-dark', // rgba(3, 51, 99, 1) - Figma var: Primary/Dark
        ],
        disabled: [
          'text-text-light', // rgba(143, 141, 150, 1) - Figma var: Text/Light
          'opacity-50',
        ],
      },
    },
    defaultVariants: {
      size: 'lg',
      state: 'default',
    },
  }
);
