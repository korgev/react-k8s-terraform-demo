import { useState, useEffect } from 'react'

// Build-time env vars injected by Vite (set in CI/CD via --build-arg or .env)
const BUILD_VERSION  = import.meta.env.VITE_APP_VERSION   || 'v1.0.0'
const BUILD_SHA      = import.meta.env.VITE_COMMIT_SHA    || 'local'
const BUILD_TIME     = import.meta.env.VITE_BUILD_TIME    || new Date().toISOString()
const ENVIRONMENT    = import.meta.env.VITE_ENVIRONMENT   || 'local'
const CLUSTER_NAME   = import.meta.env.VITE_CLUSTER_NAME  || 'react-k8s-cluster'

const services = [
  { name: 'Kubernetes Cluster',    status: 'HEALTHY',  detail: 'kind v1.32 · 2 nodes'        },
  { name: 'GitLab CI/CD',          status: 'HEALTHY',  detail: 'Pipeline #' + BUILD_SHA.slice(0,6) },
  { name: 'Container Registry',    status: 'HEALTHY',  detail: 'GitLab CE · 192.168.2.2:5050'          },
  { name: 'Traefik v3',         status: 'HEALTHY',  detail: 'traefik v3 · active'       },
  { name: 'Prometheus',            status: 'HEALTHY',  detail: 'kube-prometheus-stack'        },
  { name: 'Grafana',               status: 'HEALTHY',  detail: 'dashboards ready'             },
]

function StatusDot({ status }) {
  return <span className={`dot dot--${status.toLowerCase()}`} aria-label={status} />
}

function ServiceCard({ name, status, detail, index }) {
  return (
    <div className="card" style={{ animationDelay: `${index * 80}ms` }}>
      <div className="card__header">
        <StatusDot status={status} />
        <span className="card__name">{name}</span>
      </div>
      <div className="card__detail">{detail}</div>
      <div className={`card__badge card__badge--${status.toLowerCase()}`}>{status}</div>
    </div>
  )
}

function MetaRow({ label, value, mono = false }) {
  return (
    <div className="meta__row">
      <span className="meta__label">{label}</span>
      <span className={`meta__value${mono ? ' meta__value--mono' : ''}`}>{value}</span>
    </div>
  )
}

export default function App() {
  const [uptime, setUptime] = useState(0)
  const [tick, setTick]     = useState(false)

  useEffect(() => {
    const id = setInterval(() => {
      setUptime(s => s + 1)
      setTick(t => !t)
    }, 1000)
    return () => clearInterval(id)
  }, [])

  const fmtUptime = s => {
    const h = String(Math.floor(s / 3600)).padStart(2, '0')
    const m = String(Math.floor((s % 3600) / 60)).padStart(2, '0')
    const sec = String(s % 60).padStart(2, '0')
    return `${h}:${m}:${sec}`
  }

  return (
    <main className="app">
      {/* Ambient grid */}
      <div className="grid-bg" aria-hidden="true" />

      {/* ── Header ──────────────────────────────────── */}
      <header className="hero">
        <div className="hero__eyebrow">
          <span className="pill pill--env">{ENVIRONMENT}</span>
          <span className="hero__ticker">
            <span className={`ticker__dot${tick ? ' ticker__dot--on' : ''}`} />
            LIVE · {fmtUptime(uptime)}
          </span>
        </div>

        <h1 className="hero__title">
          K8S<span className="hero__title--accent">WEBAPP</span>
        </h1>
        <p className="hero__sub">Kubernetes · GitLab CI/CD · Terraform · Prometheus</p>
      </header>


      {/* ── About ───────────────────────────────────── */}
      <section className="section" aria-label="About this project">
        <h2 className="section__heading">
          <span className="section__line" />
          About this project
          <span className="section__line" />
        </h2>
        <div className="about">
          <p className="about__text">
            A production-grade infrastructure demo: this React app was built by GitLab CI,
            packaged as a Docker image, pushed to a self-hosted registry, deployed to a
            Kind Kubernetes cluster provisioned by Terraform, and exposed publicly via
            Traefik v3 + ngrok — all running on a local MacBook. The deployment info
            below reflects the actual CI pipeline that built and shipped this page.
          </p>
          <div className="about__stack">
            <div className="about__item">
              <span className="about__icon">⬡</span>
              <span className="about__label">Provisioned with Terraform</span>
              <span className="about__desc">Kind cluster, namespaces, RBAC, Ingress, HPA, PDB — all declared as code using reusable modules</span>
            </div>
            <div className="about__item">
              <span className="about__icon">⬡</span>
              <span className="about__label">Deployed via GitLab CI/CD</span>
              <span className="about__desc">4-stage pipeline: lint → build → push to registry → deploy to K8s with auto-rollback on failure</span>
            </div>
            <div className="about__item">
              <span className="about__icon">⬡</span>
              <span className="about__label">Observed with Prometheus + Grafana</span>
              <span className="about__desc">Full metrics stack via kube-prometheus-stack — pod health, resource usage, node metrics</span>
            </div>
            <div className="about__item">
              <span className="about__icon">⬡</span>
              <span className="about__label">Exposed via Traefik v3 + ngrok</span>
              <span className="about__desc">Ingress controller routes traffic — static ngrok domain provides HTTPS public access without a cloud LB</span>
            </div>
          </div>
        </div>
      </section>

      {/* ── Service Grid ────────────────────────────── */}
      <section className="section" aria-label="Service status">
        <h2 className="section__heading">
          <span className="section__line" />
          System Status
          <span className="section__line" />
        </h2>
        <div className="grid">
          {services.map((s, i) => (
            <ServiceCard key={s.name} {...s} index={i} />
          ))}
        </div>
      </section>

      {/* ── Build Meta ──────────────────────────────── */}
      <section className="section" aria-label="Build metadata">
        <h2 className="section__heading">
          <span className="section__line" />
          Deployment Info
          <span className="section__line" />
        </h2>
        <div className="meta">
          <MetaRow label="Version"      value={BUILD_VERSION} mono />
          <MetaRow label="Git SHA"      value={BUILD_SHA}     mono />
          <MetaRow label="Cluster"      value={CLUSTER_NAME}       />
          <MetaRow label="Built at"     value={new Date(BUILD_TIME).toLocaleString()} />
          <MetaRow label="Environment"  value={ENVIRONMENT.toUpperCase()} />
        </div>
      </section>

      {/* ── Footer ──────────────────────────────────── */}
      <footer className="footer">
        <span>Provisioned with Terraform · Deployed via GitLab CI</span>
        <span className="footer__ver">{BUILD_VERSION} · {BUILD_SHA.slice(0, 7)}</span>
      </footer>
    </main>
  )
}
