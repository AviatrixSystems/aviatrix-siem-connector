import { cva } from 'class-variance-authority';

export const segmentedButtonVariants = cva(
  // Base classes with theme tokens (container styles)
  'inline-flex items-start gap-2 p-1 bg-background-default border border-border-default rounded-lg',
  {
    variants: {
      // Figma "Style" property
      style: {
        default: '',
        badge: '',
        icon: '',
      },
    },
    defaultVariants: {
      style: 'default',
    },
  }
);
