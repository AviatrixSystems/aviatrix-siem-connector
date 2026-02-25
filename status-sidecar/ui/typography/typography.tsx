import * as React from 'react';
import { cn } from '@/lib/utils';
import { type VariantProps } from 'class-variance-authority';
import {
  labelVariants,
  paragraphVariants,
  captionVariants,
} from './typography.variants';

export const H1 = React.forwardRef<
  HTMLHeadingElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, children, ...props }, ref) => (
  <h1
    ref={ref}
    className={cn('text-text-dark text-2xl leading-10 font-normal', className)}
    {...props}
  >
    {children}
  </h1>
));
H1.displayName = 'H1';

export const H2 = React.forwardRef<
  HTMLHeadingElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, children, ...props }, ref) => (
  <h2
    ref={ref}
    className={cn('text-text-dark text-xl leading-8 font-normal', className)}
    {...props}
  >
    {children}
  </h2>
));
H2.displayName = 'H2';

export const H3 = React.forwardRef<
  HTMLHeadingElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, children, ...props }, ref) => (
  <h3
    ref={ref}
    className={cn('text-text-dark text-xl leading-6 font-normal', className)}
    {...props}
  >
    {children}
  </h3>
));
H3.displayName = 'H3';

export const H4 = React.forwardRef<
  HTMLHeadingElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, children, ...props }, ref) => (
  <h4
    ref={ref}
    className={cn('text-text-dark text-md leading-5 font-normal', className)}
    {...props}
  >
    {children}
  </h4>
));
H4.displayName = 'H4';

export const H5 = React.forwardRef<
  HTMLHeadingElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, children, ...props }, ref) => (
  <h5
    ref={ref}
    className={cn(
      'text-text-dark text-base leading-5 font-semibold',
      className
    )}
    {...props}
  >
    {children}
  </h5>
));
H5.displayName = 'H5';
export interface ParagraphProps
  extends
    React.HTMLAttributes<HTMLParagraphElement>,
    VariantProps<typeof paragraphVariants> {}

export const Paragraph = React.forwardRef<HTMLParagraphElement, ParagraphProps>(
  ({ className, variant, ...props }, ref) => (
    <p
      ref={ref}
      className={cn(paragraphVariants({ variant }), className)}
      {...props}
    />
  )
);
Paragraph.displayName = 'Paragraph';

export interface TypographyLabelProps
  extends
    React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof labelVariants> {}

export const Label = React.forwardRef<HTMLSpanElement, TypographyLabelProps>(
  ({ className, variant, ...props }, ref) => (
    <span
      ref={ref}
      className={cn(labelVariants({ variant }), className)}
      {...props}
    />
  )
);
Label.displayName = 'Label';

export interface CaptionProps
  extends
    React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof captionVariants> {}

export const Caption = React.forwardRef<HTMLSpanElement, CaptionProps>(
  ({ className, variant, ...props }, ref) => (
    <span
      ref={ref}
      className={cn(captionVariants({ variant }), className)}
      {...props}
    />
  )
);
Caption.displayName = 'Caption';
