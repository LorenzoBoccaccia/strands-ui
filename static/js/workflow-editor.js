// Workflow Editor JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Get workflow ID
    const workflowId = document.getElementById('workflow-id').value;
    console.log('Workflow editor initialized with ID:', workflowId);
    
    // Initialize jsPlumb
    const jsPlumbInstance = jsPlumb.getInstance({
        Endpoint: ["Dot", { radius: 2 }],
        Connector: ["Bezier", { curviness: 50 }],
        HoverPaintStyle: { stroke: "#dc3545", strokeWidth: 3 },
        ConnectionOverlays: [
            ["Arrow", { location: 1, width: 10, length: 10, id: "arrow" }],
            ["Label", { 
                label: "Click to delete", 
                id: "label", 
                cssClass: "connection-label",
                visible: false
            }]
        ],
        Container: "workflow-canvas"
    });
    
    const canvas = document.getElementById('workflow-canvas');
    let nodes = {};
    let edges = {};
    let connecting = false;
    let sourceNodeId = null;
    
    // Initialize drag and drop with a slight delay to ensure DOM is fully processed
    setTimeout(function() {
        initDragAndDrop();
        console.log('Drag and drop initialized');
    }, 500);
    
    // Initialize drag and drop functionality
    function initDragAndDrop() {
        // Get all draggable items
        const draggableItems = document.querySelectorAll('.draggable-item');
        
        // Add dragstart event listener to each item
        draggableItems.forEach(function(item) {
            item.addEventListener('dragstart', function(e) {
                const data = {
                    type: this.getAttribute('data-type'),
                    id: this.getAttribute('data-id'),
                    name: this.getAttribute('data-name')
                };
                
                e.dataTransfer.setData('text/plain', JSON.stringify(data));
                e.dataTransfer.effectAllowed = 'copy';
                console.log('Drag started:', data);
            });
        });
        
        // Add dragover event listener to canvas
        canvas.addEventListener('dragover', function(e) {
            e.preventDefault();
            e.dataTransfer.dropEffect = 'copy';
        });
        
        // Add drop event listener to canvas
        canvas.addEventListener('drop', function(e) {
            e.preventDefault();
            
            try {
                // Get the data
                const dataStr = e.dataTransfer.getData('text/plain');
                if (!dataStr) {
                    console.error('No data received in drop event');
                    return;
                }
                
                console.log('Drop data received:', dataStr);
                const data = JSON.parse(dataStr);
                
                // Calculate position relative to canvas
                const rect = canvas.getBoundingClientRect();
                const x = e.clientX - rect.left;
                const y = e.clientY - rect.top;
                
                // Create node on the backend
                const xhr = new XMLHttpRequest();
                xhr.open('POST', `/api/workflow/${workflowId}/nodes`, true);
                xhr.setRequestHeader('Content-Type', 'application/json');
                xhr.onload = function() {
                    if (xhr.status === 200) {
                        const response = JSON.parse(xhr.responseText);
                        createNode(response.id, data.type, data.id, x, y, data.name);
                    } else {
                        console.error('Error creating node:', xhr.statusText);
                        alert('Failed to create node: ' + xhr.statusText);
                    }
                };
                xhr.onerror = function() {
                    console.error('Error creating node:', xhr.statusText);
                    alert('Failed to create node: ' + xhr.statusText);
                };
                // For input/output nodes, use null for reference_id since they don't reference external entities
                const referenceId = (data.type === 'input' || data.type === 'output') ? null : data.id;
                
                xhr.send(JSON.stringify({
                    node_type: data.type,
                    reference_id: referenceId,
                    position_x: x,
                    position_y: y
                }));
            } catch (err) {
                console.error('Error processing drop:', err);
                alert('Error processing drop: ' + err.message);
            }
        });
    }
    
    // Create a node
    window.createNode = function(nodeId, type, referenceId, x, y, name) {
        // Create node element
        const nodeEl = document.createElement('div');
        nodeEl.id = `node-${nodeId}`;
        nodeEl.className = `node ${type}-node`;
        nodeEl.style.left = `${x}px`;
        nodeEl.style.top = `${y}px`;
        
        // Add node content
        let nodeTitle = name;
        let nodeIcon = '';
        
        if (type === 'input') {
            nodeTitle = 'Input (Start)';
            nodeIcon = '<i class="fas fa-sign-in-alt me-1"></i>';
        } else if (type === 'output') {
            nodeTitle = 'Output (End)';
            nodeIcon = '<i class="fas fa-sign-out-alt me-1"></i>';
        } else if (type === 'agent') {
            nodeIcon = '<i class="fas fa-robot me-1"></i>';
            nodeTitle = name || `Agent ${referenceId}`;
        } else if (type === 'tool') {
            nodeIcon = '<i class="fas fa-tools me-1"></i>';
            nodeTitle = name || `Tool ${referenceId}`;
        }
        
        nodeEl.innerHTML = `
            <div class="node-title">${nodeIcon} ${nodeTitle}</div>
            <div class="node-controls">
                <button class="btn btn-sm btn-outline-primary connect-btn">
                    <i class="fas fa-link"></i>
                </button>
                <button class="btn btn-sm btn-outline-danger delete-btn">
                    <i class="fas fa-times"></i>
                </button>
            </div>
        `;
        
        canvas.appendChild(nodeEl);
        
        // Store node data
        nodes[nodeId] = {
            element: nodeEl,
            type: type,
            referenceId: referenceId
        };
        
        // Make node draggable with jsPlumb
        jsPlumbInstance.draggable(nodeEl, {
            containment: "parent",
            stop: function(event) {
                // Get the new position
                const position = nodeEl.getBoundingClientRect();
                const canvasPosition = canvas.getBoundingClientRect();
                const x = position.left - canvasPosition.left;
                const y = position.top - canvasPosition.top;
                
                // Update node position in backend
                const xhr = new XMLHttpRequest();
                xhr.open('PUT', `/api/workflow/${workflowId}/nodes/${nodeId}`, true);
                xhr.setRequestHeader('Content-Type', 'application/json');
                xhr.send(JSON.stringify({
                    position_x: x,
                    position_y: y
                }));
            }
        });
        
        // Add endpoints based on node type
        if (type === 'input') {
            // Input nodes can only have outgoing connections
            jsPlumbInstance.addEndpoint(nodeEl, {
                anchor: "Right",
                isSource: true,
                maxConnections: -1
            });
        } else if (type === 'output') {
            // Output nodes can only have incoming connections
            jsPlumbInstance.addEndpoint(nodeEl, {
                anchor: "Left",
                isTarget: true,
                maxConnections: -1
            });
        } else {
            // Regular nodes have both incoming and outgoing connections
            jsPlumbInstance.addEndpoint(nodeEl, {
                anchor: "Right",
                isSource: true,
                maxConnections: -1
            });
            
            jsPlumbInstance.addEndpoint(nodeEl, {
                anchor: "Left",
                isTarget: true,
                maxConnections: -1
            });
        }
        
        // Connect button handler
        const connectBtn = nodeEl.querySelector('.connect-btn');
        connectBtn.addEventListener('click', function() {
            if (connecting) {
                connecting = false;
                document.querySelectorAll('.node').forEach(function(n) {
                    n.classList.remove('connecting');
                });
                sourceNodeId = null;
            } else {
                connecting = true;
                sourceNodeId = nodeId;
                document.querySelectorAll('.node').forEach(function(n) {
                    n.classList.remove('connecting');
                });
                nodeEl.classList.add('connecting');
            }
        });
        
        // Node click handler for creating connections
        nodeEl.addEventListener('click', function() {
            if (connecting && sourceNodeId !== nodeId) {
                // Create edge on the backend
                const xhr = new XMLHttpRequest();
                xhr.open('POST', `/api/workflow/${workflowId}/edges`, true);
                xhr.setRequestHeader('Content-Type', 'application/json');
                xhr.onload = function() {
                    if (xhr.status === 200) {
                        const response = JSON.parse(xhr.responseText);
                        createEdge(response.id, sourceNodeId, nodeId);
                        connecting = false;
                        document.querySelectorAll('.node').forEach(function(n) {
                            n.classList.remove('connecting');
                        });
                        sourceNodeId = null;
                    }
                };
                xhr.send(JSON.stringify({
                    source_node_id: sourceNodeId,
                    target_node_id: nodeId
                }));
            }
        });
        
        // Delete button handler
        const deleteBtn = nodeEl.querySelector('.delete-btn');
        deleteBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            
            // Delete node on the backend
            const xhr = new XMLHttpRequest();
            xhr.open('DELETE', `/api/workflow/${workflowId}/nodes/${nodeId}`, true);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    // Remove all connections
                    jsPlumbInstance.remove(nodeEl);
                    delete nodes[nodeId];
                }
            };
            xhr.send();
        });
    }
    
    // Create an edge
    window.createEdge = function(edgeId, sourceId, targetId) {
        const connection = jsPlumbInstance.connect({
            source: `node-${sourceId}`,
            target: `node-${targetId}`,
            deleteEndpointsOnDetach: false
        });
        
        edges[edgeId] = {
            connection: connection,
            sourceId: sourceId,
            targetId: targetId
        };
        
        // Show delete label on hover
        connection.bind('mouseenter', function() {
            connection.showOverlay('label');
        });
        
        connection.bind('mouseexit', function() {
            connection.hideOverlay('label');
        });
        
        // Add delete handler
        connection.bind('click', function() {
            if (confirm('Delete this connection?')) {
                const xhr = new XMLHttpRequest();
                xhr.open('DELETE', `/api/workflow/${workflowId}/edges/${edgeId}`, true);
                xhr.onload = function() {
                    if (xhr.status === 200) {
                        jsPlumbInstance.deleteConnection(connection);
                        delete edges[edgeId];
                    }
                };
                xhr.send();
            }
        });
    }
    
    // Function to capture the workflow canvas as an image
    function captureCanvas() {
        try {
            // Create a temporary canvas for our icon
            const tempCanvas = document.createElement('canvas');
            const ctx = tempCanvas.getContext('2d');
            
            // Set a reasonable size for the icon
            tempCanvas.width = 128;
            tempCanvas.height = 128;
            
            // Fill with a gradient background
            const gradient = ctx.createLinearGradient(0, 0, 128, 128);
            gradient.addColorStop(0, '#4361ee');
            gradient.addColorStop(1, '#3f37c9');
            ctx.fillStyle = gradient;
            ctx.fillRect(0, 0, 128, 128);
            
            // Draw a simple diagram representation
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
            ctx.lineWidth = 3;
            
            // Draw some connection lines
            ctx.beginPath();
            ctx.moveTo(30, 40);
            ctx.lineTo(60, 60);
            ctx.lineTo(90, 40);
            ctx.stroke();
            
            ctx.beginPath();
            ctx.moveTo(30, 80);
            ctx.lineTo(60, 60);
            ctx.lineTo(90, 80);
            ctx.stroke();
            
            // Draw some nodes
            ctx.fillStyle = '#cfe2ff';
            ctx.beginPath();
            ctx.arc(30, 40, 10, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#d1ecf1';
            ctx.beginPath();
            ctx.arc(60, 60, 15, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#d4edda';
            ctx.beginPath();
            ctx.arc(90, 40, 10, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#f8d7da';
            ctx.beginPath();
            ctx.arc(30, 80, 10, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            ctx.fillStyle = '#fff3cd';
            ctx.beginPath();
            ctx.arc(90, 80, 10, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
            
            // Return the data URL
            return tempCanvas.toDataURL('image/png');
        } catch (e) {
            console.error("Error capturing canvas:", e);
            return null;
        }
    }
    
    // Update workflow details
    document.getElementById('workflow-details-form').addEventListener('submit', function(e) {
        e.preventDefault();
        
        const name = document.getElementById('workflow-name').value;
        const description = document.getElementById('workflow-description').value;
        const model_id = document.getElementById('workflow-model').value;
        const saveIcon = document.getElementById('save-graph-icon').checked;
        
        // Prepare data for the API call
        const data = {
            name: name,
            description: description,
            model_id: model_id,
            generate_icon: saveIcon
        };
        
        // If saving icon is enabled, capture the canvas
        if (saveIcon) {
            const canvasData = captureCanvas();
            if (canvasData) {
                data.canvas_data = canvasData;
            }
        }
        
        // Update workflow details
        const xhr = new XMLHttpRequest();
        xhr.open('PUT', `/api/workflow/${workflowId}`, true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.onload = function() {
            if (xhr.status === 200) {
                alert('Workflow details updated successfully');
            } else {
                alert('Error updating workflow details: ' + xhr.responseText);
            }
        };
        xhr.onerror = function() {
            alert('Error updating workflow details: ' + xhr.statusText);
        };
        xhr.send(JSON.stringify(data));
    });
});
