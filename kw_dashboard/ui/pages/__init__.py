from . import cluster, node, alerts, pulse, explore, logs

registry = {
    "cluster": cluster.render,
    "node": node.render,
    "alerts": alerts.render,
    "pulse": pulse.render,
    "explore": explore.render,
    "namespace": explore.render_namespace,
    "pod": explore.render_pod,
    "logs": logs.render,
}
