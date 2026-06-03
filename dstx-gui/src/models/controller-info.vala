/*
 * controller-info.vala - Detailed controller information model for DSTX GUI
 *
 * Copyright (C) 2026 André Lameira
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * RESPONSIBILITIES:
 * - Store detailed controller information (product name, serial, driver)
 * - Maintain list of input nodes (path and name)
 */

// src/models/controller-info.vala

namespace Dstx.Models {
    public class ControllerDetailedInfo : Object {
        public string product_name { get; set; }
        public string serial { get; set; }
        public string driver { get; set; }
        private List<InputNode> _input_nodes;
        
        public ControllerDetailedInfo() {
            this.product_name = "";
            this.serial = "";
            this.driver = "";
            this._input_nodes = new List<InputNode>();
        }
        
        public unowned List<InputNode> get_input_nodes() {
            return _input_nodes;
        }
        
        public void add_input_node(string path, string name) {
            _input_nodes.append(new InputNode(path, name));
        }
        
        public class InputNode : Object {
            public string path { get; set; }
            public string name { get; set; }
            
            public InputNode(string path, string name) {
                this.path = path;
                this.name = name;
            }
        }
    }
}
