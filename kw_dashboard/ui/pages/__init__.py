from . import cluster, node

registry = {
    "cluster": cluster.render,
    "node": node.render,
}
