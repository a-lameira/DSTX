/*
 * texture-cache-manager.vala - GPU texture cache manager with LRU policy for DSTX GUI
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
 * - Manage GPU texture cache with LRU eviction policy
 * - Limit cache size to prevent excessive VRAM usage
 * - Provide cache invalidation by key prefix
 * - Support texture retrieval and storage
 */

// src/services/texture-cache-manager.vala

using Gdk;
using Gtk;

namespace Dstx.Services {
    /**
     * TextureCacheManager - Manages GPU texture cache with LRU policy
     * 
     * Features:
     * - Textures reside in VRAM, not in RAM
     * - Cache limited to MAX_CACHE_SIZE items
     * - LRU policy: least recently used textures are removed when limit is reached
     * - Cache key: arbitrary string (combination of theme + colors + size)
     * 
     * Usage:
     *   var cache = TextureCacheManager.get_default();
     *   var texture = cache.get(key);
     *   if (texture == null) {
     *       texture = create_texture();
     *       cache.put(key, texture);
     *   }
     */
    public class TextureCacheManager : Object {
        private static TextureCacheManager? instance = null;
        
        private GLib.HashTable<string, Gdk.Texture?> cache;
        private Gee.List<string> access_order;
        private const int MAX_CACHE_SIZE = 10;
        
        private TextureCacheManager() {
            cache = new GLib.HashTable<string, Gdk.Texture?>(str_hash, str_equal);
            access_order = new Gee.ArrayList<string>();
            message("TextureCacheManager: Initialized (max=%d)", MAX_CACHE_SIZE);
        }
        
        public static TextureCacheManager get_default() {
            if (instance == null) {
                instance = new TextureCacheManager();
            }
            return instance;
        }
        
        /**
         * Retrieves a texture from the cache
         * 
         * @param key Unique key to identify the texture
         * @return Texture from cache or null if not found
         */
        public Gdk.Texture? get(string key) {
            if (cache.contains(key)) {
                // Move to the end of the list (most recent)
                access_order.remove(key);
                access_order.add(key);
                message("TextureCacheManager: Cache HIT for key='%s'", key);
                return cache.get(key);
            }
            
            message("TextureCacheManager: Cache MISS for key='%s'", key);
            return null;
        }
        
        /**
         * Adds a texture to the cache
         * 
         * @param key Unique key to identify the texture
         * @param texture Texture to be stored
         */
        public void put(string key, Gdk.Texture texture) {
            // If already exists, remove first
            if (cache.contains(key)) {
                message("TextureCacheManager: Replacing existing texture: key='%s'", key);
                cache.remove(key);
                access_order.remove(key);
            }
            
            // Evict old textures if necessary
            while (access_order.size >= MAX_CACHE_SIZE) {
                string oldest = access_order[0];
                access_order.remove_at(0);
                var old_texture = cache.get(oldest);
                if (old_texture != null) {
                    message("TextureCacheManager: Evicting old texture from cache: key='%s'", oldest);
                    old_texture = null;
                }
                cache.remove(oldest);
            }
            
            // Add to cache
            cache.set(key, texture);
            access_order.add(key);
            message("TextureCacheManager: Texture added to cache: key='%s', cache_size=%d", 
                    key, access_order.size);
        }
        
        /**
         * Checks if a key exists in the cache
         * 
         * @param key Key to check
         * @return true if the key exists in the cache
         */
        public bool contains(string key) {
            return cache.contains(key);
        }
        
        /**
         * Removes a specific texture from the cache
         * 
         * @param key Key of the texture to remove
         */
        public void remove(string key) {
            if (cache.contains(key)) {
                var texture = cache.get(key);
                if (texture != null) {
                    texture = null;
                }
                cache.remove(key);
                access_order.remove(key);
                message("TextureCacheManager: Texture removed from cache: key='%s'", key);
            }
        }
        
        /**
         * Removes all textures whose key starts with a given prefix
         * Useful for invalidating all textures of a specific theme
         * 
         * @param prefix Key prefix (e.g., "light:" or "dark:")
         */
        public void invalidate_by_prefix(string prefix) {
            var to_remove = new Gee.ArrayList<string>();
            foreach (var key in cache.get_keys()) {
                if (key.has_prefix(prefix)) {
                    to_remove.add(key);
                }
            }
            
            foreach (var key in to_remove) {
                var texture = cache.get(key);
                if (texture != null) {
                    texture = null;
                }
                cache.remove(key);
                access_order.remove(key);
                message("TextureCacheManager: Texture invalidated by prefix: key='%s'", key);
            }
            
            if (to_remove.size > 0) {
                message("TextureCacheManager: %d textures removed by prefix '%s'", 
                        to_remove.size, prefix);
            }
        }
        
        /**
		 * Invalidates all textures in the cache (useful when theme changes).
		 */
		public void invalidate_all() {
		    clear();
		    message("TextureCacheManager: All textures invalidated");
		}

        /**
         * Clears the entire cache
         */
        public void clear() {
            foreach (var key in cache.get_keys()) {
                var texture = cache.get(key);
                if (texture != null) {
                    texture = null;
                }
            }
            cache.remove_all();
            access_order.clear();
            message("TextureCacheManager: Cache completely cleared");
        }
        
        /**
         * Returns the current cache size
         */
        public int size() {
            return access_order.size;
        }
        
        /**
         * Returns the maximum cache size
         */
        public int max_size() {
            return MAX_CACHE_SIZE;
        }
        
        /**
         * Logs the current cache state (for debugging)
         */
        public void log_cache_state() {
            message("TextureCacheManager: Cache state - size=%d/%d", 
                    access_order.size, MAX_CACHE_SIZE);
            int i = 0;
            foreach (var key in access_order) {
                message("  [%d] %s", i, key);
                i++;
            }
        }
        
        ~TextureCacheManager() {
            clear();
            message("TextureCacheManager: Destroyed");
        }
    }
}
