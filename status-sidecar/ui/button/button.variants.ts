import { cva } from 'class-variance-authority';

export const buttonVariants = cva(
  'inline-flex items-center justify-center whitespace-nowrap rounded-xs text-md font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none hover:cursor-pointer',
  {
    variants: {
      intent: {
        primary:
          'bg-primary text-text-dark-inverse hover:bg-primary-medium active:bg-primary-dark disabled:bg-primary-disabled disabled:text-text-dark-inverse',
        secondary:
          'border border-primary text-primary hover:bg-primary-transparent active:bg-primary-light disabled:text-primary-disabled disabled:border-primary-disabled disabled:bg-background',
        tertiary:
          'text-primary hover:bg-primary-transparent active:bg-primary-light disabled:text-primary-disabled',
      },
      size: {
        lg: 'h-8 px-2 py-1 gap-1',
        md: 'h-6 px-2 py-1 gap-1',
        sm: 'h-4 px-2 py-1 gap-1',
      },
      loading: {
        false: null,
        true: null,
      },
      attention: {
        false: null,
        true: null,
      },
    },
    compoundVariants: [
      {
        intent: 'primary',
        attention: true,
        class:
          'bg-error text-text-dark-inverse hover:bg-error-medium active:bg-error-dark disabled:bg-error-disabled disabled:text-text-dark-inverse',
      },
      {
        intent: 'secondary',
        attention: true,
        class:
          'border border-error text-error hover:bg-error-transparent active:bg-error-light disabled:text-error-disabled disabled:border-error-disabled disabled:bg-background',
      },
      {
        intent: 'tertiary',
        attention: true,
        class:
          'text-error hover:bg-error-light active:bg-error-medium disabled:text-error-disabled',
      },
    ],
    defaultVariants: {
      intent: 'primary',
      size: 'lg',
      attention: false,
      loading: false,
    },
  }
);
export type ButtonVariantClassNames = ReturnType<typeof buttonVariants>;
