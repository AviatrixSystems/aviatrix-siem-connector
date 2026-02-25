import * as React from 'react';
import { type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';
import { Info, CircleCheck, OctagonAlert, CircleAlert } from 'lucide-react';
import {
  badgeVariants,
  badgeTextVariants,
  badgeIconVariants,
} from './badge.variants';

export interface BadgeProps
  extends
    Omit<React.HTMLAttributes<HTMLDivElement>, 'style'>,
    VariantProps<typeof badgeVariants> {
  children?: React.ReactNode;
  number?: number;
}

const stateIconMap: Record<
  string,
  React.ComponentType<React.SVGProps<SVGSVGElement>>
> = {
  info: Info,
  success: CircleCheck,
  warning: OctagonAlert,
  error: CircleAlert,
  disabled: CircleAlert,
  default: CircleAlert,
};

export const Badge = React.forwardRef<HTMLDivElement, BadgeProps>(
  (
    { className, style: badgeStyle, state, bold, children, number, ...props },
    ref
  ) => {
    const IconComponent =
      stateIconMap[state || 'default'] || stateIconMap.default;

    return (
      <div
        ref={ref}
        className={cn(
          badgeVariants({ style: badgeStyle, state, bold }),
          className
        )}
        {...props}
      >
        {badgeStyle === 'dot' && <div className="h-full w-full rounded-full" />}

        {badgeStyle === 'number' && (
          <span className={cn(badgeTextVariants({ style: badgeStyle }))}>
            {number ?? 1}
          </span>
        )}

        {badgeStyle === 'icon' && (
          <IconComponent
            className={cn(badgeIconVariants({ style: badgeStyle }))}
            strokeWidth={3}
          />
        )}

        {badgeStyle === 'default' && (
          <>
            <IconComponent
              className={cn(badgeIconVariants({ style: badgeStyle }), 'mr-1')}
              strokeWidth={3}
            />
            <span className={cn(badgeTextVariants({ style: badgeStyle }))}>
              {children || state}
            </span>
          </>
        )}
      </div>
    );
  }
);

Badge.displayName = 'Badge';
