import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import {
  Globe,
  Ban,
  Info,
  CircleEllipsis,
  CheckCircle,
  ArrowUpCircle,
  AlertTriangle,
  CircleDot,
  XCircle,
  ArrowDownCircle,
  AlertCircle,
  CircleDashed,
  type LucideIcon,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Paragraph } from '@/ui/typography';

// Status variant configuration
const statusVariants = cva('inline-flex items-center gap-1', {
  variants: {
    variant: {
      icon: '',
      bars: '',
    },
    state: {
      default: '',
      unknown: '',
      disabled: '',
      info: '',
      progress: '',
      success: '',
      up: '',
      warning: '',
      error: '',
      down: '',
      degraded: '',
      critical: '',
    },
  },
  defaultVariants: {
    variant: 'icon',
    state: 'default',
  },
});

// State color Tailwind classes (for when no custom color is provided)
const stateColorClasses = {
  default: 'text-text-medium',
  unknown: 'text-text-medium',
  disabled: 'text-text-medium',
  info: 'text-primary',
  progress: 'text-primary',
  success: 'text-success',
  up: 'text-success',
  warning: 'text-warning',
  error: 'text-error',
  down: 'text-error',
  degraded: 'text-warning',
  critical: 'text-error',
} as const;

// State CSS variable colors (for use in bars and custom color fallbacks)
const stateColors = {
  default: 'var(--Text-Medium)',
  unknown: 'var(--Text-Medium)',
  disabled: 'var(--Text-Medium)',
  info: 'var(--Primary-Default)',
  progress: 'var(--Primary-Default)',
  success: 'var(--Success-Default)',
  up: 'var(--Success-Default)',
  warning: 'var(--Warning-Default)',
  error: 'var(--Error-Default)',
  down: 'var(--Error-Default)',
  degraded: 'var(--Warning-Default)',
  critical: 'var(--Error-Default)',
} as const;

const barColorOverrides = {
  success: 'var(--Reserved-Green-Medium)',
  warning: 'var(--Reserved-Yellow-Medium)',
  error: 'var(--Reserved-Red-Medium)',
} as const;

// Number of bars to fill based on state (for bars style)
const barFillCount = {
  default: 4,
  unknown: 2,
  disabled: 1,
  info: 4,
  progress: 4,
  success: 1, // "Low"
  up: 4,
  warning: 2, // "Medium"
  error: 3, // "High"
  down: 0,
  degraded: 2,
  critical: 4,
} as const;

export interface StatusProps
  extends
    Omit<React.HTMLAttributes<HTMLDivElement>, 'style'>,
    VariantProps<typeof statusVariants> {
  /**
   * The variant of the status indicator
   * @default "icon"
   */
  variant?: 'icon' | 'bars';

  /**
   * The state to display
   * @default "default"
   */
  state?:
    | 'default'
    | 'unknown'
    | 'disabled'
    | 'info'
    | 'progress'
    | 'success'
    | 'up'
    | 'warning'
    | 'error'
    | 'down'
    | 'degraded'
    | 'critical';

  /**
   * Custom icon component (only applies to icon variant)
   */
  icon?: LucideIcon;

  /**
   * The text label to display
   */
  children?: React.ReactNode;

  /**
   * Custom color for the icon or bars (overrides state-based color)
   */
  color?: string;

  /**
   * Custom text color (overrides default text color)
   */
  textColor?: string;

  /**
   * Whether the status is animated (only applies to progress state with icon variant)
   * @default false
   */
  animated?: boolean;
}

const StatusIcon = ({
  state,
  animated = false,
  customIcon,
  customColor,
}: {
  state: NonNullable<StatusProps['state']>;
  animated?: boolean;
  customIcon?: LucideIcon;
  customColor?: string;
}) => {
  const iconMap = {
    default: Globe,
    unknown: CircleDashed,
    disabled: Ban,
    info: Info,
    progress: CircleEllipsis,
    success: CheckCircle,
    up: ArrowUpCircle,
    warning: AlertTriangle,
    error: AlertCircle,
    down: ArrowDownCircle,
    degraded: CircleDot,
    critical: XCircle,
  } as const;

  const IconComponent = customIcon || iconMap[state];

  // Use Tailwind classes when no custom color, otherwise use inline style
  const iconClass = cn(
    'shrink-0',
    'size-4',
    state === 'progress' && animated && 'animate-spin',
    !customColor && stateColorClasses[state]
  );

  // Only use inline style when custom color is provided
  const iconStyle = customColor ? { color: customColor } : undefined;

  return (
    <IconComponent
      className={iconClass}
      style={iconStyle}
      strokeWidth={1.5}
      aria-hidden="true"
    />
  );
};

const StatusBars = ({
  state,
  customColor,
}: {
  state: NonNullable<StatusProps['state']>;
  customColor?: string;
}) => {
  const fillCount = barFillCount[state];
  const colorToken =
    barColorOverrides[state as keyof typeof barColorOverrides] ||
    stateColors[state];
  const activeColorStyle = customColor || colorToken;
  const inactiveColorStyle = 'var(--Background-Default)';

  return (
    <div className="inline-flex items-end gap-0.5" aria-hidden="true">
      <div
        className="h-1 w-0.5"
        style={{
          backgroundColor:
            fillCount >= 1 ? activeColorStyle : inactiveColorStyle,
        }}
      />
      <div
        className="h-1.5 w-0.5"
        style={{
          backgroundColor:
            fillCount >= 2 ? activeColorStyle : inactiveColorStyle,
        }}
      />
      <div
        className="h-2 w-0.5"
        style={{
          backgroundColor:
            fillCount >= 3 ? activeColorStyle : inactiveColorStyle,
        }}
      />
      <div
        className="h-2.5 w-0.5"
        style={{
          backgroundColor:
            fillCount >= 4 ? activeColorStyle : inactiveColorStyle,
        }}
      />
    </div>
  );
};

const Status = React.forwardRef<HTMLDivElement, StatusProps>(
  (
    {
      className,
      variant = 'icon',
      state = 'default',
      icon,
      children,
      color,
      textColor,
      animated = false,
      ...props
    },
    ref
  ) => {
    return (
      <div
        ref={ref}
        className={cn(statusVariants({ variant, state }), className)}
        role="status"
        style={{
          color: textColor || undefined,
        }}
        {...props}
      >
        {variant === 'icon' ? (
          <StatusIcon
            state={state}
            animated={animated}
            customIcon={icon}
            customColor={color}
          />
        ) : (
          <StatusBars state={state} customColor={color} />
        )}
        {children && (
          <Paragraph
            className="whitespace-nowrap"
            style={textColor ? { color: textColor } : undefined}
          >
            {children}
          </Paragraph>
        )}
      </div>
    );
  }
);

Status.displayName = 'Status';

export { Status };
// eslint-disable-next-line react-refresh/only-export-components
export { statusVariants };
