import React from 'react';
import { useTheme } from 'next-themes';
import { Toaster as Sonner, toast as sonnerToast } from 'sonner';
import { Info, CheckCircle, AlertTriangle, AlertCircle, X } from 'lucide-react';
import { Button } from '@/ui/button';
import { H5, Paragraph } from '@/ui/typography';

type ToasterProps = React.ComponentProps<typeof Sonner>;

const Toaster = ({ position = 'top-right', ...props }: ToasterProps) => {
  const themeContext = useTheme();
  if (!themeContext) {
    throw new TypeError('useTheme returned undefined');
  }

  return (
    <Sonner theme="light" position={position} className="toaster" {...props} />
  );
};

export { Toaster };

export type ToastTone = 'neutral' | 'info' | 'success' | 'warning' | 'error';

export interface AppToastAction {
  label: string;
  onClick?: () => void;
}

export interface AppToastProps {
  id?: string | number;
  title?: string;
  description?: string;
  tone?: ToastTone;
  action?: AppToastAction;
  /** Duration in milliseconds before the toast auto-dismisses. Set to Infinity to disable auto-dismiss. */
  duration?: number;
}

const toneToBadgeBg: Record<ToastTone, string> = {
  neutral: 'bg-background-medium',
  info: 'bg-primary-light',
  success: 'bg-success-light',
  warning: 'bg-warning-light',
  error: 'bg-error-light',
};

// Helper function to get stroke width safely (client-side only)
const getStrokeWidth = (): number => {
  if (typeof window === 'undefined' || typeof document === 'undefined') {
    return 1.5; // Default fallback for SSR
  }
  return (
    Number(
      getComputedStyle(document.documentElement).getPropertyValue(
        '--icon-stroke'
      )
    ) || 1.5
  );
};

const toneToIcon: Record<ToastTone, React.ReactNode> = {
  neutral: (
    <Info
      className="text-text-medium size-3"
      strokeWidth={getStrokeWidth()}
      aria-hidden="true"
    />
  ),
  info: (
    <Info
      className="text-primary-dark size-3"
      strokeWidth={getStrokeWidth()}
      aria-hidden="true"
    />
  ),
  success: (
    <CheckCircle
      className="text-success-dark size-3"
      strokeWidth={getStrokeWidth()}
      aria-hidden="true"
    />
  ),
  warning: (
    <AlertTriangle
      className="text-warning-dark size-3"
      strokeWidth={getStrokeWidth()}
      aria-hidden="true"
    />
  ),
  error: (
    <AlertCircle
      className="text-error-dark size-3"
      strokeWidth={getStrokeWidth()}
      aria-hidden="true"
    />
  ),
};

interface ToastCardProps {
  id: string | number;
  title?: string;
  description?: string;
  tone: ToastTone;
  action?: AppToastAction;
}

function ToastCard(props: ToastCardProps) {
  const { id, title, description, tone, action } = props;
  // Explicitly check if title exists - don't render H5 if title is undefined, null, or empty
  const hasTitle = Boolean(title);
  return (
    <div className="border-border-light bg-background-light text-text-dark relative flex w-80 flex-col items-start rounded-md border shadow-md">
      <div className="flex items-start gap-4 p-4">
        <span
          className={`rounded-round-md inline-flex shrink-0 items-center justify-center p-1 ${toneToBadgeBg[tone]}`}
        >
          {toneToIcon[tone]}
        </span>
        <div className="min-w-0 flex-1">
          {hasTitle ? <H5 className="text-text-medium">{title}</H5> : null}
          {description ? (
            <Paragraph
              variant="default"
              className={`text-text-medium${hasTitle ? 'mt-1' : ''}`}
            >
              {description}
            </Paragraph>
          ) : null}
        </div>
      </div>
      {action ? (
        <>
          <div className="bg-border-light h-px w-full" />
          <div className="flex h-8 w-full items-center justify-end px-4">
            <Button
              intent="tertiary"
              size="md"
              onClick={() => {
                action.onClick?.();
                sonnerToast.dismiss(id);
              }}
            >
              {action.label}
            </Button>
          </div>
        </>
      ) : null}
      <button
        type="button"
        aria-label="Close"
        onClick={() => sonnerToast.dismiss(id)}
        className="border-border-light bg-background-default text-text-medium hover:bg-background-medium focus-visible:ring-primary focus-visible:ring-md absolute -top-2.5 -right-2.5 rounded-lg border p-1 focus-visible:ring-offset-2 focus-visible:outline-none"
      >
        <X className="size-3" aria-hidden="true" />
      </button>
      <div className="bg-border-light absolute inset-x-1 bottom-0 h-0.5">
        <div className="bg-primary h-full w-full" />
      </div>
    </div>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function showToast(toast: Omit<AppToastProps, 'id'>) {
  // Explicitly set title to undefined if not provided to prevent any default behavior
  const title = toast.title !== undefined ? toast.title : undefined;

  return sonnerToast.custom(
    id => (
      <ToastCard
        id={id}
        title={title}
        description={toast.description}
        tone={toast.tone ?? 'neutral'}
        action={toast.action}
      />
    ),
    { duration: toast.duration }
  );
}
