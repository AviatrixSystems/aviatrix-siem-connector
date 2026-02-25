import { cva } from 'class-variance-authority';

export const segmentVariants = cva(
  // Base classes with theme tokens
  'inline-flex items-center justify-center rounded-lg px-2 py-1 h-6 gap-1 transition-colors cursor-pointer',
  {
    variants: {
      // Figma "State" property
      state: {
        default: 'text-text-medium hover:bg-theme-transparent',
        hover: 'bg-theme-transparent text-text-medium',
        active: 'bg-theme-light text-text-dark',
        disabled:
          'text-text-light cursor-not-allowed opacity-60 pointer-events-none',
      },
    },
    defaultVariants: {
      state: 'default',
    },
  }
);
