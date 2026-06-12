/*
 * thumbnail-cache.vala - Permanent cache for theme thumbnails
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
 */

using Gdk;

namespace Dstx.Services {
    /**
     * ThumbnailCache - Permanent cache for theme thumbnails.
     * Thumbnails are rendered once and kept for the entire application lifetime.
     */
    public class ThumbnailCache : Object {
        private static ThumbnailCache? instance = null;
        private GLib.HashTable<string, Gdk.Texture?> cache;
        
        private ThumbnailCache() {
            cache = new GLib.HashTable<string, Gdk.Texture?>(str_hash, str_equal);
            message("ThumbnailCache: Initialized (permanent storage)");
        }
        
        public static ThumbnailCache get_default() {
            if (instance == null) {
                instance = new ThumbnailCache();
            }
            return instance;
        }
        
        /**
         * Retrieves a texture from the cache.
         * @param key Unique key (e.g., "light:160x100")
         * @return Texture or null if not found
         */
        public Gdk.Texture? get_texture(string key) {
            return cache.get(key);
        }
        
        /**
         * Stores a texture in the cache.
         * @param key Unique key
         * @param texture Texture to store
         */
        public void put(string key, Gdk.Texture texture) {
            cache.set(key, texture);
            message("ThumbnailCache: Stored texture for key='%s'", key);
        }
        
        /**
         * Removes a specific texture.
         * @param key Key to remove
         */
        public void remove(string key) {
            var texture = cache.get(key);
            if (texture != null) {
                texture = null;
                cache.remove(key);
                message("ThumbnailCache: Removed texture for key='%s'", key);
            }
        }
        
        /**
         * Clears all thumbnails from the cache.
         */
        public void clear() {
            foreach (var key in cache.get_keys()) {
                var texture = cache.get(key);
                if (texture != null) texture = null;
                cache.remove(key);
            }
            message("ThumbnailCache: Cleared all thumbnails");
        }
        
        /**
         * Checks if a key exists.
         */
        public bool contains(string key) {
            return cache.contains(key);
        }
        
        /**
         * Returns the number of cached thumbnails.
         */
        public uint size() {
            return cache.size();
        }
    }
}
