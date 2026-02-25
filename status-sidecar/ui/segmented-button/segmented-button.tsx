import { type VariantProps } from 'class-variance-authority';
import * as React from 'react';
import { cn } from '@/lib/utils';
import { Badge } from '@/ui/badge';
import { Segment } from '@/ui/segment';
import { segmentedButtonVariants } from './segmented-button.variants';

// Props interface matching Figma properties EXACTLY
export interface SegmentedButtonProps
  extends
    Omit<React.HTMLAttributes<HTMLDivElement>, 'onChange' | 'style'>,
    VariantProps<typeof segmentedButtonVariants> {
  // Figma property (lowercase prop name from Figma property name)
  style?: 'default' | 'badge' | 'icon'; // Figma: "Style"

  // Additional props not in Figma
  value?: string | number; // Currently selected value
  defaultValue?: string | number; // Default selected value (uncontrolled)
  onValueChange?: (value: string | number) => void; // Change handler
  options: SegmentOption[]; // Array of segment options
  disabled?: boolean; // Disable all segments
}

export interface SegmentOption {
  value: string | number; // Unique identifier
  label?: string; // Display label (for default/badge styles)
  icon?: React.ReactNode; // Icon element (for icon style)
  badge?: number; // Badge number (for badge style only)
  disabled?: boolean; // Disable specific segment
}

const SegmentedButton = React.forwardRef<HTMLDivElement, SegmentedButtonProps>(
  (
    {
      className,
      style = 'default', // Figma default
      value,
      defaultValue,
      onValueChange,
      options,
      disabled = false,
      ...props
    },
    ref
  ) => {
    // Controlled vs uncontrolled state management
    const [internalValue, setInternalValue] = React.useState<
      string | number | undefined
    >(defaultValue);

    const selectedValue = value !== undefined ? value : internalValue;

    const handleSegmentClick = (optionValue: string | number) => {
      if (disabled) return;

      // Update internal state if uncontrolled
      if (value === undefined) {
        setInternalValue(optionValue);
      }

      // Call external handler
      onValueChange?.(optionValue);
    };

    return (
      <div
        ref={ref}
        role="radiogroup"
        className={cn(segmentedButtonVariants({ style }), className)}
        {...props}
      >
        {options.map(option => {
          const isSelected = selectedValue === option.value;
          const isDisabled = disabled || option.disabled;

          // Default style: text labels only
          if (style === 'default') {
            return (
              <Segment
                key={option.value}
                selected={isSelected}
                disabled={isDisabled}
                onClick={() => handleSegmentClick(option.value)}
              >
                {option.label}
              </Segment>
            );
          }

          // Badge style: text labels + badge numbers
          if (style === 'badge') {
            return (
              <Segment
                key={option.value}
                selected={isSelected}
                disabled={isDisabled}
                onClick={() => handleSegmentClick(option.value)}
              >
                <div className="flex items-center gap-1">
                  {option.label}
                  {option.badge !== undefined && (
                    <Badge
                      style="number"
                      number={option.badge}
                      bold={isSelected ? 'on' : 'off'}
                      className="ml-1"
                    />
                  )}
                </div>
              </Segment>
            );
          }

          // Icon style: icons only
          if (style === 'icon') {
            return (
              <Segment
                key={option.value}
                selected={isSelected}
                disabled={isDisabled}
                onClick={() => handleSegmentClick(option.value)}
              >
                {option.icon}
              </Segment>
            );
          }

          return null;
        })}
      </div>
    );
  }
);
SegmentedButton.displayName = 'SegmentedButton';

// Compound component API for easier usage with children
export interface SegmentedButtonGroupProps extends Omit<
  SegmentedButtonProps,
  'options'
> {
  children: React.ReactNode;
  size?: 'sm' | 'md' | 'lg'; // For compatibility, though not used in base component
}

export interface SegmentedButtonItemProps {
  value: string | number;
  disabled?: boolean;
  children?: React.ReactNode;
}

// Item component - doesn't render, just holds data
export const SegmentedButtonItem: React.FC<SegmentedButtonItemProps> = () => {
  return null;
};
SegmentedButtonItem.displayName = 'SegmentedButtonItem';

// Group component that converts children to options
export const SegmentedButtonGroup = React.forwardRef<
  HTMLDivElement,
  SegmentedButtonGroupProps
>(({ children, ...props }, ref) => {
  // Extract options from children
  const options: SegmentOption[] = React.Children.toArray(children)
    .filter(
      (child): child is React.ReactElement<SegmentedButtonItemProps> =>
        React.isValidElement(child) && child.type === SegmentedButtonItem
    )
    .map(child => {
      const { value, disabled, children: itemChildren } = child.props;

      // If children is a React element, treat it as an icon
      // Otherwise, treat it as a label (string/number)
      const option: SegmentOption = {
        value,
        disabled,
      };

      if (React.isValidElement(itemChildren)) {
        option.icon = itemChildren;
      } else if (itemChildren != null) {
        option.label = String(itemChildren);
      }

      return option;
    });

  return <SegmentedButton {...props} options={options} ref={ref} />;
});
SegmentedButtonGroup.displayName = 'SegmentedButtonGroup';

export { SegmentedButton };
