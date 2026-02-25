import * as React from 'react';
import { type VariantProps } from 'class-variance-authority';
import { ChevronDown, Folder } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Paragraph } from '@/ui/typography';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
  TooltipProvider,
} from '@/ui/tooltip';
import { navigationItemVariants } from './navigation-item.variants';
import { useNavigation } from './navigation';

/**
 * NavigationItem Props
 *
 * Props interface matching Figma properties for navigation items.
 *
 * Figma Designs:
 * - Level 1: https://www.figma.com/design/floUsFzaaTXQeI0aNygqj9/Essential-Components?node-id=508-42196
 * - Level 2: https://www.figma.com/design/floUsFzaaTXQeI0aNygqj9/Essential-Components?node-id=645-28053
 */
export interface NavigationItemProps
  extends
    Omit<React.HTMLAttributes<HTMLDivElement>, 'title'>,
    VariantProps<typeof navigationItemVariants> {
  /**
   * Navigation level
   * @figma "Variant" property
   * @default "level-1"
   */
  level?: 'level-1' | 'level-2';

  /**
   * Navigation type (vertical sidebar or horizontal nav)
   * @figma "Type" property
   * @default "vertical"
   */
  type?: 'vertical' | 'horizontal';

  /**
   * Visual state
   * @figma "State" property
   * @default "default"
   */
  state?: 'default' | 'hover' | 'active' | 'expanded';

  /**
   * Navigation item title/label
   */
  title: string;

  /**
   * Icon to display (Level 1 only)
   * Defaults to Folder icon if not provided
   */
  icon?: React.ReactNode;

  /**
   * Whether the item has children and can be expanded (Level 1 only)
   * Shows expand/collapse chevron when true
   * @default false
   */
  expandable?: boolean;

  /**
   * Whether the item is currently expanded (Level 1 only)
   * Controls chevron direction (right vs down)
   * @default false
   */
  expanded?: boolean;

  /**
   * Click handler for the navigation item
   */
  onSelect?: () => void;

  /**
   * Toggle handler for expand/collapse (Level 1 only)
   */
  onToggle?: () => void;
}

/**
 * NavigationItem Component
 *
 * A navigation item component for sidebar and horizontal navigation menus.
 * Supports two levels of hierarchy with appropriate visual treatments.
 *
 * Level 1: Top-level navigation with icon, title, and optional expand chevron
 * Level 2: Nested navigation with indent line and title only
 *
 * @example
 * ```tsx
 * // Level 1 - Basic
 * <NavigationItem title="Dashboard" icon={<Home />} />
 *
 * // Level 1 - Expandable
 * <NavigationItem
 *   title="Settings"
 *   icon={<Settings />}
 *   expandable
 *   expanded={isExpanded}
 *   onToggle={() => setIsExpanded(!isExpanded)}
 * />
 *
 * // Level 2 - Nested item
 * <NavigationItem level="level-2" title="Account Settings" />
 *
 * // Active state
 * <NavigationItem title="Dashboard" state="active" />
 * ```
 */
export const NavigationItem = React.forwardRef<
  HTMLDivElement,
  NavigationItemProps
>(
  (
    {
      className,
      level = 'level-1',
      type = 'vertical',
      state = 'default',
      title,
      icon,
      expandable = false,
      expanded = false,
      onSelect,
      onToggle,
      onClick,
      ...props
    },
    ref
  ) => {
    // Get collapsed state from Navigation context
    const { collapsed } = useNavigation();

    // Track if title is truncated
    const titleRef = React.useRef<HTMLParagraphElement>(null);
    const [isTruncated, setIsTruncated] = React.useState(false);

    // Check if text is truncated
    React.useEffect(() => {
      const checkTruncation = () => {
        if (titleRef.current) {
          setIsTruncated(
            titleRef.current.scrollWidth > titleRef.current.clientWidth
          );
        }
      };

      checkTruncation();

      // Re-check on resize
      window.addEventListener('resize', checkTruncation);
      return () => window.removeEventListener('resize', checkTruncation);
    }, [title]);

    // Hide Level-2 items when navigation is collapsed
    if (collapsed && level === 'level-2') {
      return null;
    }

    // Determine effective state - if expanded, use expanded state
    const effectiveState = expanded && expandable ? 'expanded' : state;

    // Handle click on the item
    const handleClick = (e: React.MouseEvent<HTMLDivElement>) => {
      onClick?.(e);

      // If expandable, toggle on click
      if (expandable && onToggle) {
        onToggle();
      } else if (onSelect) {
        onSelect();
      }
    };

    // Handle keyboard navigation
    const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        if (expandable && onToggle) {
          onToggle();
        } else if (onSelect) {
          onSelect();
        }
      }
    };

    // Determine icon size based on nav type
    const iconSize = type === 'vertical' ? 'size-icon-xl' : 'size-icon-lg';

    return (
      <div
        ref={ref}
        className={cn(
          navigationItemVariants({ level, type, state: effectiveState }),
          className
        )}
        onClick={handleClick}
        onKeyDown={handleKeyDown}
        role="button"
        tabIndex={0}
        aria-expanded={expandable ? expanded : undefined}
        {...props}
      >
        {/* Left spacing/padding */}
        <div className="flex w-4 shrink-0 items-center">
          {/* Level 2: Show divider line for horizontal nav */}
          {level === 'level-2' && type === 'horizontal' && (
            <div className="bg-theme-medium rounded-2xs h-5 w-px" />
          )}
        </div>

        {/* Center content area */}
        <div className="flex h-full min-w-0 flex-1 items-stretch gap-2">
          {/* Icon + Title section */}
          <div className="flex min-w-0 flex-1 items-center gap-2">
            {/* Level 1: Show icon */}
            {level === 'level-1' && (
              <div
                className={cn(
                  'flex shrink-0 items-center justify-center',
                  iconSize
                )}
              >
                {icon || (
                  <Folder className={cn('text-text-dark-inverse', iconSize)} />
                )}
              </div>
            )}

            {/* Level 2: Show indent with divider */}
            {level === 'level-2' && type === 'vertical' && (
              <div className="w-icon-xl mx-[calc(var(--spacing-sm)*1.5)] flex shrink-0 items-center justify-center self-stretch">
                <div className="bg-theme-transparent rounded-2xs h-full w-px" />
              </div>
            )}

            {/* Title */}
            <div className="flex min-w-0 flex-1 flex-col items-start justify-center overflow-hidden">
              {isTruncated ? (
                <TooltipProvider delayDuration={300}>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Paragraph
                        ref={titleRef}
                        className="text-text-dark-inverse w-full truncate"
                      >
                        {title}
                      </Paragraph>
                    </TooltipTrigger>
                    <TooltipContent side="right" align="center">
                      {title}
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              ) : (
                <Paragraph
                  ref={titleRef}
                  className="text-text-dark-inverse w-full truncate"
                >
                  {title}
                </Paragraph>
              )}
            </div>
          </div>

          {/* Expand/Collapse chevron (Level 1 only, when expandable) */}
          {level === 'level-1' && expandable && (
            <div className="flex shrink-0 items-center">
              <div className="p-xs flex items-center justify-center rounded-xs">
                <ChevronDown
                  className={cn(
                    'text-text-dark-inverse size-icon-md transition-transform duration-200',
                    expanded && '-rotate-180'
                  )}
                />
              </div>
            </div>
          )}
        </div>

        {/* Right spacing/padding */}
        <div className="flex w-4 shrink-0 items-center justify-end">
          {/* Level 2: Show divider line for horizontal nav on hover */}
          {level === 'level-2' &&
            type === 'horizontal' &&
            effectiveState === 'hover' && (
              <div className="bg-theme-medium rounded-2xs h-5 w-px" />
            )}
        </div>
      </div>
    );
  }
);

NavigationItem.displayName = 'NavigationItem';
