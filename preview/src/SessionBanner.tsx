import type { SessionAction, SessionBannerModel } from './domain/sessionBanner';

export function SessionBanner({
  model,
  onAction,
}: {
  model: SessionBannerModel;
  onAction: (action: SessionAction) => void;
}) {
  return (
    <section
      className={`session-banner session-banner--${model.phase}`}
      data-testid="session-banner"
      data-tone={model.tone}
      aria-labelledby="session-banner-title"
    >
      <div className="session-banner-heading">
        <h2 id="session-banner-title">{model.title}</h2>
        {model.clockLabel && (
          <p className="session-clock" aria-hidden="true">
            {model.clockLabel}
          </p>
        )}
      </div>
      <p className="session-banner-message">{model.message}</p>
      {model.action && model.actionLabel && (
        <button type="button" className="session-action" onClick={() => onAction(model.action!)}>
          {model.actionLabel}
        </button>
      )}
    </section>
  );
}
