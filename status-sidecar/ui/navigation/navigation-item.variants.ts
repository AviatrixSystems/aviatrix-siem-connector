import { cva } from 'class-variance-authority';

/**
 * Navigation Item Variants
 *
 * Based on Figma designs:
 * - Level 1: https://www.figma.com/design/floUsFzaaTXQeI0aNygqj9/Essential-Components?node-id=508-42196
 * - Level 2: https://www.figma.com/design/floUsFzaaTXQeI0aNygqj9/Essential-Components?node-id=645-28053
 */
export const navigationItemVariants = cva(
  // Base styles: 240px width, 40px height, flex layout
  'flex h-xl max-w-surface-2xs items-center transition-colors',
  {
    variants: {
      /**
       * Navigation level variant
       * - level-1: Top-level nav with icon, title, and expand chevron
       * - level-2: Nested nav with indent line and title only
       */
      level: {
        'level-1': '',
        'level-2': '',
      },

      /**
       * Navigation type
       * - vertical: For sidebar navigation (full width)
       * - horizontal: For horizontal nav bars (content width)
       */
      type: {
        vertical: 'w-full',
        horizontal: '',
      },

      /**
       * Visual state from Figma
       * - default: Normal state (theme-dark background)
       * - hover: Mouse hover (theme-medium background)
       * - active: Selected/active item (theme-default background)
       * - expanded: Item is expanded showing children (same as default but with rotated chevron)
       */
      state: {
        default: 'bg-theme-dark',
        hover: 'bg-theme-medium',
        active: 'bg-theme-default',
        expanded: 'bg-theme-dark',
      },
    },

    compoundVariants: [
      // Hover interactions for non-active states
      {
        state: 'default',
        class: 'hover:bg-theme-medium cursor-pointer',
      },
      {
        state: 'expanded',
        class: 'hover:bg-theme-medium cursor-pointer',
      },
      // Active state maintains its background on hover
      {
        state: 'active',
        class: 'hover:bg-theme-default cursor-pointer',
      },
    ],

    defaultVariants: {
      level: 'level-1',
      type: 'vertical',
      state: 'default',
    },
  }
);
