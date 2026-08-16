from . import cluster, node, alerts, pulse

registry = {
    "cluster": cluster.render,
    "node": node.render,
    "alerts": alerts.render,
    "pulse": pulse.render,
}
