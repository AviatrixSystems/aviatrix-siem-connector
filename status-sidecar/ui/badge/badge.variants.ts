import { cva } from 'class-variance-authority';

export const badgeVariants = cva(
  'inline-flex items-center justify-center font-sans font-normal text-center whitespace-nowrap',
  {
    variants: {
      style: {
        default: 'px-2 py-1 h-5 rounded-round-md',
        dot: 'size-2 rounded-round-sm',
        number: 'px-1 h-3 rounded-round-sm min-w-[12px]',
        icon: 'p-1 h-5 w-5 rounded-round-md',
      },
      state: {
        default: 'bg-background-medium text-text-dark',
        info: 'bg-primary-light text-primary-dark',
        success: 'bg-success-light text-success-dark',
        warning: 'bg-warning-light text-warning-dark',
        error: 'bg-error-light text-error-dark',
        disabled: 'bg-background-default text-text-light',
      },
      bold: {
        off: '',
        on: '',
      },
    },
    compoundVariants: [
      // Bold variants for default state
      {
        style: 'default',
        state: 'default',
        bold: 'on',
        class: 'bg-theme-default text-text-dark-inverse',
      },
      {
        style: 'default',
        state: 'info',
        bold: 'on',
        class: 'bg-primary text-text-dark-inverse',
      },
      {
        style: 'default',
        state: 'success',
        bold: 'on',
        class: 'bg-success text-text-dark-inverse',
      },
      {
        style: 'default',
        state: 'warning',
        bold: 'on',
        class: 'bg-warning text-text-dark-inverse',
      },
      {
        style: 'default',
        state: 'error',
        bold: 'on',
        class: 'bg-error text-text-dark-inverse',
      },
      {
        style: 'default',
        state: 'disabled',
        bold: 'on',
        class: 'bg-theme-dark text-text-light',
      },
      // Bold variants for dot state
      {
        style: 'dot',
        state: 'default',
        bold: 'on',
        class: 'bg-theme-default',
      },
      {
        style: 'dot',
        state: 'info',
        bold: 'on',
        class: 'bg-primary',
      },
      {
        style: 'dot',
        state: 'success',
        bold: 'on',
        class: 'bg-success',
      },
      {
        style: 'dot',
        state: 'warning',
        bold: 'on',
        class: 'bg-warning',
      },
      {
        style: 'dot',
        state: 'error',
        bold: 'on',
        class: 'bg-error',
      },
      // Bold variants for number state
      {
        style: 'number',
        state: 'default',
        bold: 'on',
        class: 'bg-theme-default text-text-dark-inverse',
      },
      {
        style: 'number',
        state: 'info',
        bold: 'on',
        class: 'bg-primary text-text-dark-inverse',
      },
      {
        style: 'number',
        state: 'success',
        bold: 'on',
        class: 'bg-success text-text-dark-inverse',
      },
      {
        style: 'number',
        state: 'warning',
        bold: 'on',
        class: 'bg-warning text-text-dark-inverse',
      },
      {
        style: 'number',
        state: 'error',
        bold: 'on',
        class: 'bg-error text-text-dark-inverse',
      },
      // Bold variants for icon state
      {
        style: 'icon',
        state: 'default',
        bold: 'on',
        class: 'bg-theme-default text-text-dark-inverse',
      },
      {
        style: 'icon',
        state: 'info',
        bold: 'on',
        class: 'bg-primary text-text-dark-inverse',
      },
      {
        style: 'icon',
        state: 'success',
        bold: 'on',
        class: 'bg-success text-text-dark-inverse',
      },
      {
        style: 'icon',
        state: 'warning',
        bold: 'on',
        class: 'bg-warning text-text-dark-inverse',
      },
      {
        style: 'icon',
        state: 'error',
        bold: 'on',
        class: 'bg-error text-text-dark-inverse',
      },
    ],
    defaultVariants: {
      style: 'default',
      state: 'default',
      bold: 'off',
    },
  }
);

export const badgeTextVariants = cva('', {
  variants: {
    style: {
      default: 'text-sm leading-5 font-normal',
      number: 'text-2xs leading-[8px] font-normal',
      dot: '',
      icon: '',
    },
  },
  defaultVariants: {
    style: 'default',
  },
});

export const badgeIconVariants = cva('', {
  variants: {
    style: {
      default: 'size-icon-sm',
      icon: 'size-icon-sm',
      number: '',
      dot: '',
    },
  },
  defaultVariants: {
    style: 'default',
  },
});
