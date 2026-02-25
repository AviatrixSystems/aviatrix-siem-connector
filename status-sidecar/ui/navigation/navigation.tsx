import * as React from 'react';
import { cn } from '@/lib/utils';

/**
 * Navigation Container Props
 */
export interface NavigationProps extends React.HTMLAttributes<HTMLElement> {
  /**
   * Navigation orientation
   * @default "vertical"
   */
  orientation?: 'vertical' | 'horizontal';

  /**
   * Whether to collapse to icons only (vertical nav)
   * @default false
   */
  collapsed?: boolean;
}

/**
 * Navigation Context for sharing state across navigation items
 */
interface NavigationContextValue {
  orientation: 'vertical' | 'horizontal';
  collapsed: boolean;
}

const NavigationContext = React.createContext<NavigationContextValue>({
  orientation: 'vertical',
  collapsed: false,
});

/**
 * Hook to access navigation context
 */
// eslint-disable-next-line react-refresh/only-export-components
export const useNavigation = () => React.useContext(NavigationContext);

/**
 * Navigation Component
 *
 * Container component for NavigationItem components. Provides consistent
 * styling and context for vertical sidebar or horizontal navigation patterns.
 *
 * @example
 * ```tsx
 * // Vertical sidebar navigation
 * <Navigation orientation="vertical">
 *   <NavigationItem title="Dashboard" icon={<Home />} state="active" />
 *   <NavigationItem
 *     title="Settings"
 *     icon={<Settings />}
 *     expandable
 *     expanded={settingsExpanded}
 *     onToggle={() => setSettingsExpanded(!settingsExpanded)}
 *   />
 *   {settingsExpanded && (
 *     <>
 *       <NavigationItem level="level-2" title="Account" />
 *       <NavigationItem level="level-2" title="Security" />
 *     </>
 *   )}
 * </Navigation>
 *
 * // Horizontal navigation
 * <Navigation orientation="horizontal">
 *   <NavigationItem title="Home" type="horizontal" />
 *   <NavigationItem title="Products" type="horizontal" />
 *   <NavigationItem title="About" type="horizontal" />
 * </Navigation>
 * ```
 */
export const Navigation = React.forwardRef<HTMLElement, NavigationProps>(
  (
    {
      className,
      orientation = 'vertical',
      collapsed = false,
      children,
      ...props
    },
    ref
  ) => {
    const contextValue = React.useMemo(
      () => ({ orientation, collapsed }),
      [orientation, collapsed]
    );

    return (
      <NavigationContext.Provider value={contextValue}>
        <nav
          ref={ref}
          className={cn(
            'flex',
            orientation === 'vertical'
              ? 'w-surface-2xs bg-theme-dark flex-col'
              : 'bg-theme-dark flex-row',
            collapsed && orientation === 'vertical' && 'w-auto',
            className
          )}
          data-orientation={orientation}
          {...props}
        >
          {children}
        </nav>
      </NavigationContext.Provider>
    );
  }
);

Navigation.displayName = 'Navigation';

/**
 * NavigationGroup Component
 *
 * Groups related navigation items together with an optional label.
 *
 * @example
 * ```tsx
 * <Navigation>
 *   <NavigationGroup label="Main">
 *     <NavigationItem title="Dashboard" />
 *     <NavigationItem title="Analytics" />
 *   </NavigationGroup>
 *   <NavigationGroup label="Settings">
 *     <NavigationItem title="Account" />
 *     <NavigationItem title="Security" />
 *   </NavigationGroup>
 * </Navigation>
 * ```
 */
export interface NavigationGroupProps extends React.HTMLAttributes<HTMLDivElement> {
  /**
   * Optional group label
   */
  label?: string;
}

export const NavigationGroup = React.forwardRef<
  HTMLDivElement,
  NavigationGroupProps
>(({ className, label, children, ...props }, ref) => {
  const { collapsed } = useNavigation();

  return (
    <div ref={ref} className={cn('flex flex-col', className)} {...props}>
      {label && !collapsed && (
        <div className="text-text-dark-inverse/60 px-4 py-2 text-xs font-semibold tracking-wider uppercase">
          {label}
        </div>
      )}
      {children}
    </div>
  );
});

NavigationGroup.displayName = 'NavigationGroup';
