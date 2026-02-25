import { cva } from 'class-variance-authority';

const paragraphVariants = cva('text-text-dark text-base', {
  variants: {
    variant: {
      default: 'leading-5 font-normal',
      highlight: 'leading-5 font-semibold',
      italic: 'leading-5 italic',
      console: 'leading-4.5 font-normal font-mono',
    },
  },
  defaultVariants: {
    variant: 'default',
  },
});

const labelVariants = cva('text-text-dark text-sm', {
  variants: {
    variant: {
      default: 'leading-5 font-normal',
      highlight: 'leading-5 font-semibold',
      italic: 'leading-4 italic',
      paragraph: 'leading-4 font-normal',
    },
  },
  defaultVariants: {
    variant: 'default',
  },
});

const captionVariants = cva('text-text-dark font-normal', {
  variants: {
    variant: {
      default: 'text-sm leading-5 font-normal text-right',
      highlight: 'text-sm leading-5 font-semibold text-right',
      badge: 'text-xs leading-[12px] font-normal text-center',
    },
  },
  defaultVariants: {
    variant: 'default',
  },
});

export { labelVariants, paragraphVariants, captionVariants };
