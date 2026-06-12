/*
 * thumbnail-renderer.vala - Theme thumbnail rendering service for DSTX GUI
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
 * - Render theme thumbnails using Cairo
 * - Draw window background, sidebars, cards, controller silhouette, border
 * - Cache rendered thumbnails via TextureCacheManager
 */

// src/services/thumbnail-renderer.vala

using Cairo;
using Gdk;
using Gtk;
using Graphene;
using Dstx.Models;

namespace Dstx.Services {
    public class ThumbnailRenderer : Object {
        
        private const int WIDTH = 160;
        private const int HEIGHT = 100;
        
        private const double CANVAS_WIDTH = 1723.2095;
        private const double CANVAS_HEIGHT = 1077.0059;
        private const double OFFSET = 23.951675;
        
        private double scale;
        private double offset_x;
        private double offset_y;
        
        public ThumbnailRenderer() {
            double scale_x = WIDTH / CANVAS_WIDTH;
            double scale_y = HEIGHT / CANVAS_HEIGHT;
            scale = double.min(scale_x, scale_y);
            offset_x = (WIDTH - (CANVAS_WIDTH * scale)) / 2;
            offset_y = (HEIGHT - (CANVAS_HEIGHT * scale)) / 2;
            
            message("ThumbnailRenderer: Initialized (scale=%.4f)", scale);
        }
        
		public Gdk.Texture? get_thumbnail(ThemeData theme, int target_width, int target_height) {
    			string cache_key = @"$(theme.id):$(target_width)x$(target_height)";
    			var cache = ThumbnailCache.get_default();
    
    			var cached = cache.get_texture(cache_key);
    			if (cached != null) {
    			    message("ThumbnailRenderer: Cache hit for %s", cache_key);
    			    return cached;
    			}
    		
    			message("ThumbnailRenderer: Cache miss for %s, rendering...", cache_key);
    			var texture = render_to_texture(theme, target_width, target_height);
    			if (texture != null) {
    			    cache.put(cache_key, texture);
    			}
    			return texture;
		}
    	    
		private Gdk.Texture? render_to_texture(ThemeData theme, int target_width, int target_height) {
    			message("render_to_texture: Starting for theme %s, size %dx%d", theme.id, target_width, target_height);
    
    			var snapshot = new Gtk.Snapshot();
    
    			Graphene.Rect bounds = Graphene.Rect();
    			bounds.init(0.0f, 0.0f, (float)target_width, (float)target_height);
    			var cr = snapshot.append_cairo(bounds);
    
    			// Save original values
    			double old_scale = scale;
    			double old_offset_x = offset_x;
    			double old_offset_y = offset_y;
    	
    			// Recalculate scale based on CANVAS
    			double scale_x = (double)target_width / CANVAS_WIDTH;
    			double scale_y = (double)target_height / CANVAS_HEIGHT;
    			scale = double.min(scale_x, scale_y);
    
    			// Center the drawing
    			offset_x = (target_width - (CANVAS_WIDTH * scale)) / 2;
    			offset_y = (target_height - (CANVAS_HEIGHT * scale)) / 2;
    
    			message("render_to_texture: scale=%.4f, offset=(%.1f,%.1f)", scale, offset_x, offset_y);
    
    			draw_thumbnail(cr, theme);
    
    			// Restore original values
    			scale = old_scale;
    			offset_x = old_offset_x;
    			offset_y = old_offset_y;
    
    			cr = null;
    
    			var node = snapshot.free_to_node();
    			if (node == null) {
    			    warning("render_to_texture: Failed to get node for theme %s", theme.id);
    			    return null;
    			}
    
    			// Create a Cairo surface
    			var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, target_width, target_height);
    			var ctx = new Cairo.Context(surface);
    			node.draw(ctx);
    			surface.flush();
    
    			uint8* data_ptr = surface.get_data();
    			if (data_ptr == null) {
    			    warning("render_to_texture: Failed to get surface data for theme %s", theme.id);
    			    return null;
    			}
    
    			int stride = surface.get_stride();
    			size_t data_size = target_height * stride;
    
    			uint8[] data = new uint8[data_size];
    			GLib.Memory.copy(data, data_ptr, data_size);
    
    			var bytes_obj = new GLib.Bytes.take(data);
    		
    			Gdk.Texture? texture = null;
    			try {
			texture = new Gdk.MemoryTexture(target_width, target_height, 
    		                            Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, 
    		                            bytes_obj, stride);
    	    		message("render_to_texture: Texture created successfully for theme %s", theme.id);
    			} catch (GLib.Error e) {
    		    		warning("render_to_texture: Error creating texture: %s", e.message);
    		    		return null;
    			}
    
    			return texture;
		}
        
        private void draw_thumbnail(Cairo.Context cr, ThemeData theme) {
            string window_bg_str = get_theme_color_string(theme, "--window-bg", theme.thumbnail.bg);
            string sidebar_bg_str = get_theme_color_string(theme, "--sidebar-bg", theme.thumbnail.bg);
            string card_bg_str = get_theme_color_string(theme, "--card-bg", window_bg_str);
            string text_color_str = get_theme_color_string(theme, "text", theme.thumbnail.text);
            string primary_str = get_theme_color_string(theme, "primary", theme.thumbnail.bg);
            string secondary_str = get_theme_color_string(theme, "secondary", theme.thumbnail.accent);
            string border_color_str = get_theme_color_string(theme, "border", "#6d6d6d");
            
            var window_bg = parse_hex_color(window_bg_str);
            var sidebar_bg = parse_hex_color(sidebar_bg_str);
            var card_bg = parse_hex_color(card_bg_str);
            var text_color = parse_hex_color(text_color_str);
            var primary = parse_hex_color(primary_str);
            var secondary = parse_hex_color(secondary_str);
            var border_color = parse_hex_color(border_color_str);
            
            draw_window_background(cr, window_bg);
            draw_sidebar_left(cr, sidebar_bg);
            draw_sidebar_right(cr, sidebar_bg);
            draw_cards(cr, card_bg);
            draw_text_elements(cr, text_color);
            draw_controller_primary(cr, primary);
            draw_controller_secondary_path1(cr, secondary);
            draw_controller_secondary_path2(cr, secondary);
            draw_controller_secondary_path3(cr, secondary);
            draw_thumbnail_border(cr, border_color);
        }
        
        private string get_theme_color_string(ThemeData theme, string key, string fallback) {
            if (theme.window.vars.has_key(key)) {
                return theme.window.vars.get(key);
            }
            
            if (key == "primary" && theme.controller.primary != null) {
                return theme.controller.primary;
            }
            if (key == "secondary" && theme.controller.secondary != null) {
                return theme.controller.secondary;
            }
            if (key == "text" && theme.thumbnail.text != null) {
                return theme.thumbnail.text;
            }
            
            return fallback;
        }
        
        private void draw_window_background(Cairo.Context cr, Gdk.RGBA color) {
            double x = 342.47526 * scale + offset_x;
            double y = 1.2621163 * scale + offset_y;
            double width = (1311.4861 - 342.47526) * scale;
            double height = (1075.7438 - 1.2621163) * scale;
            
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            cr.rectangle(x, y, width, height);
            cr.fill();
        }
        
        private void draw_sidebar_left(Cairo.Context cr, Gdk.RGBA color) {
            cr.save();
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            
            cr.move_to((342.47526) * scale + offset_x, (1075.7438) * scale + offset_y);
            cr.line_to((342.47526) * scale + offset_x, (1.2621163) * scale + offset_y);
            cr.line_to((61.254712) * scale + offset_x, (1.2621163) * scale + offset_y);
            
            cr.curve_to((33.237445) * scale + offset_x, (1.2621163) * scale + offset_y,
                        (1.2621163) * scale + offset_x, (26.7551507) * scale + offset_y,
                        (1.2621163) * scale + offset_x, (59.9925957) * scale + offset_y);
            
            cr.line_to((1.2621163) * scale + offset_x, (1015.7512) * scale + offset_y);
            
            cr.curve_to((1.2621163) * scale + offset_x, (1048.9887) * scale + offset_y,
                        (33.237445) * scale + offset_x, (1075.7438) * scale + offset_y,
                        (61.254712) * scale + offset_x, (1075.7438) * scale + offset_y);
            
            cr.close_path();
            cr.fill();
            cr.restore();
        }
        
        private void draw_sidebar_right(Cairo.Context cr, Gdk.RGBA color) {
            cr.save();
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            
            cr.move_to((1311.4861) * scale + offset_x, (1.2621163) * scale + offset_y);
            cr.line_to((1311.4861) * scale + offset_x, (1075.7438) * scale + offset_y);
            cr.line_to((1311.4861 + 350.4476) * scale + offset_x, (1075.7438) * scale + offset_y);
            
            cr.curve_to((1311.4861 + 350.4476 + 33.2375) * scale + offset_x, (1075.7438) * scale + offset_y,
                        (1311.4861 + 350.4476 + 59.9926) * scale + offset_x, (1075.7438 - 26.7551) * scale + offset_y,
                        (1311.4861 + 350.4476 + 59.9926) * scale + offset_x, (1075.7438 - 59.9926) * scale + offset_y);
            
            cr.line_to((1311.4861 + 350.4476 + 59.9926) * scale + offset_x, (61.254712) * scale + offset_y);
            
            cr.curve_to((1311.4861 + 350.4476 + 59.9926) * scale + offset_x, (61.254712 - 33.237445) * scale + offset_y,
                        (1311.4861 + 350.4476 + 33.2375) * scale + offset_x, (1.2621163) * scale + offset_y,
                        (1311.4861 + 350.4476) * scale + offset_x, (1.2621163) * scale + offset_y);
            
            cr.close_path();
            cr.fill();
            cr.restore();
        }
        
        private void draw_cards(Cairo.Context cr, Gdk.RGBA color) {
            cr.set_source_rgba(color.red, color.green, color.blue, 0.404787);
            
            draw_card(cr, 1352.4584, 137.05281, 336.84103, 239.35983, 18.858753);
            draw_card(cr, 1352.4584, 436.25262, 336.84103, 119.67992, 18.858753);
            draw_card(cr, 1352.4584, 615.77252, 336.84103, 119.67992, 18.858753);
            draw_card(cr, 1352.4584, 795.29242, 336.84103, 59.839958, 18.858753);
            
            draw_card(cr, 38.900883, 524.82062, 270.57199, 131.71709, 17.5);
            draw_card(cr, 39.63784, 130.36192, 270.57199, 131.71709, 17.5);
            draw_card(cr, 38.919544, 332.9599, 270.57199, 131.71709, 17.5);
        }
        
        private void draw_card(Cairo.Context cr, double x, double y, double w, double h, double r) {
            x = x * scale + offset_x;
            y = y * scale + offset_y;
            w = w * scale;
            h = h * scale;
            r = r * scale;
            
            draw_rounded_rectangle(cr, x, y, w, h, r);
            cr.fill();
        }
        
        private void draw_text_elements(Cairo.Context cr, Gdk.RGBA color) {
            cr.set_source_rgba(color.red, color.green, color.blue, 0.404787);
            
            draw_rounded_rectangle(cr, 
                (765.05066 * scale + offset_x),
                (877.39355 * scale + offset_y),
                172.32408 * scale, 24.910213 * scale, 17.5 * scale);
            cr.fill();
            
            draw_rounded_rectangle(cr,
                (792.93823 * scale + offset_x),
                (913.71716 * scale + offset_y),
                112.94905 * scale, 24.910213 * scale, 11.470297 * scale);
            cr.fill();
        }
        
        private void draw_controller_primary(Cairo.Context cr, Gdk.RGBA color) {
            cr.save();
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            
            double[] points = {
                420.93624, 663.92385, 421.55416, 668.72194,
                422.75369, 676.42796, 425.18908, 683.95222,
                428.89669, 691.18570, 432.71336, 697.03792,
                437.83858, 702.99918, 442.78206, 707.61552,
                448.77968, 711.90471, 454.84998, 715.68503,
                463.57378, 719.82882, 471.64328, 723.20931,
                479.78550, 725.82645, 489.38166, 729.06151,
                500.28640, 731.75134, 510.97306, 734.04136,
                520.42384, 735.53164, 530.20175, 736.33133,
                536.69007, 736.64032, 543.06935, 736.94927,
                549.46679, 736.80385, 555.20995, 736.56761,
                561.53470, 736.05871, 567.35057, 735.25903,
                571.56706, 734.49572, 575.52913, 733.49612,
                579.45483, 731.98763, 582.34459, 730.64272,
                585.27070, 729.27958, 588.06958, 727.51668,
                590.70489, 725.48111, 593.12211, 723.15477,
                595.05440, 721.08020, 598.65278, 717.07058,
                600.96602, 713.72923, 605.79814, 705.35014,
                608.25275, 700.06823, 610.32181, 695.27467,
                612.30092, 690.27550, 614.20293, 685.13495,
                616.55473, 679.48035, 618.58524, 674.40406,
                620.46154, 669.54625, 622.02941, 665.48521,
                624.16273, 660.11335, 626.09043, 654.61296,
                627.74827, 650.25635, 629.43179, 645.30858,
                631.38519, 640.09093, 633.04302, 635.13030,
                634.84221, 630.27249, 636.66711, 624.78495,
                638.31208, 619.43878, 639.75143, 614.85085,
                640.76669, 611.97215, 641.64058, 609.71031,
                643.36266, 607.83401, 645.05904, 606.24044,
                647.50081, 604.60832, 650.10963, 603.18182,
                652.29436, 602.21797, 654.22207, 601.33122,
                655.69997, 601.22841, 656.59958, 601.47258,
                657.49917, 602.23081, 658.77145, 603.51595,
                659.96663, 604.60832, 661.77867, 605.89345,
                663.98910, 607.40990, 666.75215, 609.22194,
                668.96258, 610.45568, 672.38104, 612.28058,
                675.68384, 613.95125, 679.39789, 615.67334,
                683.36895, 617.22835, 688.57376, 618.88618,
                693.35446, 620.02995, 698.59782, 621.07090,
                704.62512, 621.91910, 710.72951, 622.30464,
                720.18810, 622.30464, 725.34151, 621.64922,
                730.43065, 620.77533, 735.03143, 619.65726,
                739.20812, 618.52634, 743.35911, 617.16409,
                746.93180, 615.80185, 750.24744, 614.25969,
                754.77112, 611.80508, 758.88356, 609.51753,
                763.44579, 606.53602, 767.68671, 603.52881,
                770.43697, 601.39548, 772.44179, 599.46778,
                773.52125, 598.38827, 925.31689, 598.38827,
                926.67091, 599.78907, 928.54726, 601.53685,
                931.16887, 603.58021, 934.17615, 605.89346,
                937.20906, 608.03964, 941.45000, 610.68702,
                944.75281, 612.43480, 949.23790, 614.56813,
                954.27564, 616.57294, 959.77606, 618.53920,
                963.96563, 619.88859, 969.50455, 621.04521,
                972.85873, 621.50787, 979.65713, 622.24039,
                985.83865, 622.49742, 989.05149, 622.49742,
                994.48758, 622.12473, 1000.48920, 621.04521,
                1005.39830, 620.23558, 1009.78070, 619.02755,
                1014.89560, 617.27977, 1019.80480, 615.44202,
                1024.93250, 612.96171, 1028.77500, 610.78983,
                1033.88980, 607.84687, 1037.25690, 605.70069,
                1039.40300, 604.03002, 1041.06090, 602.56496,
                1042.28180, 601.33123, 1044.28660, 601.33123,
                1046.70260, 602.41074, 1049.10590, 603.56737,
                1051.38050, 604.68543, 1053.37250, 605.95772,
                1054.90180, 607.17860, 1055.93000, 608.12959,
                1057.09940, 609.68461, 1057.93470, 611.75369,
                1059.01430, 615.19785, 1064.58860, 632.64542,
                1069.87740, 647.29413, 1073.73040, 657.38102,
                1076.54750, 664.52362, 1079.32830, 671.59354,
                1081.85450, 678.69978, 1084.45350, 685.29715,
                1086.47070, 690.11342, 1088.77900, 695.58396,
                1091.94140, 703.07193, 1095.97610, 710.12366,
                1100.37440, 716.92095, 1103.82750, 721.13748,
                1108.29860, 725.82649, 1112.80580, 728.91615,
                1117.34950, 731.31521, 1123.20160, 733.60523,
                1130.18080, 735.42266, 1136.54180, 736.36776,
                1149.00960, 737.20378, 1160.45950, 737.16738,
                1170.67360, 736.54950, 1180.56060, 735.38632,
                1192.33770, 733.24171, 1206.04120, 730.00664,
                1217.27320, 726.77153, 1229.01400, 722.37328,
                1239.77330, 717.86601, 1249.00600, 712.52269,
                1255.54890, 707.90635, 1260.60140, 703.14461,
                1265.39960, 697.91033, 1269.21610, 692.82145,
                1272.23310, 687.33273, 1274.17180, 682.01211,
                1276.38210, 673.27318, 1277.51310, 666.38485,
                1278.23270, 660.06198, 1282.61220, 655.58970,
                1282.50940, 643.86926, 1282.14950, 633.38255,
                1281.06990, 616.11032, 1280.04180, 603.67020,
                1277.93420, 586.34656, 1275.56960, 570.61650,
                1272.38240, 552.36757, 1269.09250, 536.74032,
                1265.39130, 519.00543, 1261.48450, 502.50429,
                1255.67570, 479.16622, 1249.91820, 455.46829,
                1242.41310, 425.96157, 1236.86130, 403.85724,
                1233.21150, 390.49181, 1229.45890, 377.38342,
                1225.03800, 364.53206, 1220.36010, 352.60601,
                1217.32720, 345.76907, 1212.18660, 334.56268,
                1209.25660, 329.21651, 1204.98990, 322.37959,
                1196.09670, 308.60291, 1187.76910, 295.59733,
                1179.85250, 281.82065, 1177.89920, 280.68972,
                1168.85180, 278.37649, 1160.31860, 276.98853,
                1151.93950, 275.85762, 1142.58370, 274.82951,
                1131.89140, 274.21265, 1115.28750, 273.44157,
                1102.07620, 273.44157, 1089.27620, 273.80140,
                1079.20080, 274.72670, 1060.18080, 277.09135,
                1055.45150, 278.06805, 1053.70360, 279.14757,
                1052.57270, 280.68972, 1051.28760, 281.76923,
                1048.10050, 283.56843, 1044.34790, 284.69934,
                1041.26360, 284.95638, 1000.24196, 284.95638,
                999.07787, 285.45658, 998.42364, 286.69245,
                998.42364, 428.63585, 998.27821, 430.59870,
                997.91474, 432.23440, 997.44224, 433.79742,
                996.13358, 436.08741, 993.97056, 439.10846,
                990.64203, 442.55262, 986.59379, 444.96869,
                983.17539, 446.35662, 979.16574, 446.76787,
                721.39823, 446.76787, 718.29895, 446.13815,
                714.54636, 444.33896, 710.87087, 441.71729,
                708.40341, 438.88998, 706.32148, 435.57433,
                704.54799, 431.71893, 703.64840, 427.86351,
                703.59710, 423.67397, 703.59710, 287.52667,
                703.18740, 286.49255, 702.35138, 285.80191,
                701.06098, 285.38390, 699.49797, 285.18398,
                662.96110, 285.18398, 660.21091, 285.08488,
                657.51211, 284.69933, 655.30169, 284.10816,
                653.34827, 283.13147, 651.54908, 282.15477,
                649.67279, 280.43269, 648.49046, 279.07044,
                646.87118, 278.01662, 644.81497, 277.34836,
                643.29851, 277.03992, 639.95716, 276.50016,
                636.77002, 276.06323, 625.76925, 274.93230,
                618.26405, 274.05842, 612.14681, 273.57006,
                605.28414, 273.26162, 581.22633, 273.26162,
                574.26089, 273.41584, 566.72999, 273.95560,
                558.63363, 274.62388, 548.89231, 275.85761,
                539.99917, 277.29696, 529.10122, 279.43029,
                526.19680, 280.27847, 524.73175, 281.04956,
                523.21528, 282.36040, 521.80164, 284.62224,
                514.83619, 296.57401, 497.16038, 323.55047,
                493.96166, 328.71205, 489.30897, 337.50855,
                484.18373, 348.81313, 479.38565, 361.35358,
                474.69661, 374.36657, 469.97122, 390.65099,
                466.95424, 402.90063, 461.97441, 421.83853,
                457.13997, 440.52200, 452.81444, 457.71514,
                447.43476, 479.92446, 441.98239, 502.27918,
                436.16653, 527.75994, 431.47749, 549.89656,
                429.16902, 562.03171, 427.00999, 576.99070,
                424.33690, 596.47336, 422.84615, 614.41386,
                422.07506, 627.41943, 421.40680, 641.81296
            };
            
            bool first = true;
            for (int i = 0; i < points.length; i += 2) {
                double x = (points[i] - OFFSET) * scale + offset_x;
                double y = (points[i+1] - OFFSET) * scale + offset_y;
                
                if (first) {
                    cr.move_to(x, y);
                    first = false;
                } else {
                    cr.line_to(x, y);
                }
            }
            
            cr.close_path();
            cr.fill();
            cr.restore();
        }
        
        private void draw_controller_secondary_path1(Cairo.Context cr, Gdk.RGBA color) {
            cr.save();
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            
            double[] points = {
                452.05110, 770.46318, 455.83141, 773.87999,
                461.21107, 778.09650, 471.02535, 785.29361,
                479.67645, 789.36474, 492.10785, 792.92696,
                507.73798, 794.45363, 520.89637, 793.94473,
                534.92715, 789.87365, 547.64934, 783.47616,
                555.57345, 777.87841, 563.06137, 771.62635,
                568.73184, 766.17397, 574.40231, 759.92191,
                580.29087, 752.65209, 585.37975, 745.89117,
                589.23275, 739.20291, 592.43147, 732.95084,
                598.60138, 721.49147, 605.79814, 705.35014,
                600.96602, 713.72923, 598.65278, 717.07058,
                595.05440, 721.08020, 593.12211, 723.15477,
                590.70489, 725.48111, 588.06958, 727.51668,
                585.27070, 729.27958, 582.34459, 730.64272,
                579.45483, 731.98763, 575.52913, 733.49612,
                571.56706, 734.49572, 567.35057, 735.25903,
                561.53470, 736.05871, 555.20995, 736.56761,
                549.46679, 736.80385, 543.06935, 736.94927,
                536.69007, 736.64032, 530.20175, 736.33133,
                520.42384, 735.53164, 510.97306, 734.04136,
                500.28640, 731.75134, 489.38166, 729.06151,
                479.78550, 725.82645, 471.64328, 723.20931,
                463.57378, 719.82882, 454.84998, 715.68503,
                448.77968, 711.90471, 442.78206, 707.61552,
                437.83858, 702.99918, 432.71336, 697.03792,
                428.89669, 691.18570, 425.18908, 683.95222,
                422.75369, 676.42796, 421.55416, 668.72194,
                420.93624, 663.92385, 420.60909, 675.95541,
                420.68179, 690.93127, 421.04528, 697.03792,
                421.77227, 704.12600, 423.18989, 712.23186,
                425.15274, 720.01058, 427.40638, 728.98881,
                429.11478, 734.44119, 432.13177, 741.78371,
                434.74892, 747.12705, 438.49287, 753.81526,
                443.40000, 760.97605, 447.18031, 765.41066
            };
            
            bool first = true;
            for (int i = 0; i < points.length; i += 2) {
                double x = (points[i] - OFFSET) * scale + offset_x;
                double y = (points[i+1] - OFFSET) * scale + offset_y;
                
                if (first) {
                    cr.move_to(x, y);
                    first = false;
                } else {
                    cr.line_to(x, y);
                }
            }
            
            cr.fill();
            cr.restore();
        }
        
        private void draw_controller_secondary_path2(Cairo.Context cr, Gdk.RGBA color) {
            cr.save();
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            
            double[] points = {
                1220.60730, 786.93056, 1225.07960, 785.07996,
                1230.01450, 782.76674, 1234.43540, 780.09367,
                1239.93570, 775.87844, 1246.20720, 770.42942,
                1252.63280, 763.84954, 1256.95090, 757.73230,
                1262.34850, 748.94197, 1266.10110, 742.10503,
                1269.49390, 733.62314, 1272.16700, 724.98701,
                1274.78870, 714.44890, 1276.12510, 706.37825,
                1277.46170, 698.41040, 1278.07860, 691.36786,
                1278.54130, 680.82974, 1278.23270, 660.06198,
                1277.51310, 666.38485, 1276.38210, 673.27318,
                1274.17180, 682.01211, 1272.23310, 687.33273,
                1269.21610, 692.82145, 1265.39960, 697.91033,
                1260.60140, 703.14461, 1255.54890, 707.90635,
                1249.00600, 712.52269, 1239.77330, 717.86601,
                1229.01400, 722.37328, 1217.27320, 726.77153,
                1206.04120, 730.00664, 1192.33770, 733.24171,
                1180.56060, 735.38632, 1170.67360, 736.54950,
                1160.45950, 737.16738, 1149.00960, 737.20378,
                1136.54180, 736.36776, 1130.18080, 735.42266,
                1123.20160, 733.60523, 1117.34950, 731.31521,
                1112.80580, 728.91615, 1108.29860, 725.82649,
                1103.82750, 721.13748, 1100.37440, 716.92095,
                1095.97610, 710.12366, 1091.94140, 703.07193,
                1101.02860, 714.66730, 1105.71760, 724.40886,
                1109.86150, 732.55109, 1113.42360, 738.83948,
                1117.82190, 745.56406, 1122.32920, 751.96155,
                1127.89070, 758.57705, 1133.67010, 765.04723,
                1139.95860, 771.26292, 1147.77370, 777.66035,
                1155.11610, 782.56750, 1161.69530, 785.80257,
                1169.25590, 789.07401, 1176.27130, 791.18224,
                1183.72290, 792.49082, 1193.68260, 793.14509,
                1202.04290, 793.10869, 1207.34980, 792.56346,
                1213.67450, 791.10945, 1219.12700, 789.43742
            };
            
            bool first = true;
            for (int i = 0; i < points.length; i += 2) {
                double x = (points[i] - OFFSET) * scale + offset_x;
                double y = (points[i+1] - OFFSET) * scale + offset_y;
                
                if (first) {
                    cr.move_to(x, y);
                    first = false;
                } else {
                    cr.line_to(x, y);
                }
            }
            
            cr.fill();
            cr.restore();
        }
        
        private void draw_controller_secondary_path3(Cairo.Context cr, Gdk.RGBA color) {
            cr.save();
            cr.set_source_rgba(color.red, color.green, color.blue, 1.0);
            
            double[] points = {
                712.43038, 282.59630, 986.30782, 282.59630,
                986.49746, 282.77142, 986.49746, 422.22008,
                986.36910, 425.37097, 985.99761, 428.01254,
                985.19271, 430.57157, 983.91322, 432.71785,
                982.01456, 434.98795, 979.82704, 436.88660,
                977.14416, 438.37248, 974.75023, 439.09478,
                972.35630, 439.42498, 727.84537, 439.42498,
                725.03869, 439.34248, 722.56221, 438.78527,
                720.00318, 437.73277, 717.98073, 436.39134,
                715.99955, 434.63718, 714.10092, 432.47026,
                712.61502, 429.99378, 711.96341, 428.10103,
                711.78829, 426.11640, 711.78829, 284.39751,
                711.78829, 282.97576, 711.91963, 282.74957,
                712.05825, 282.60363
            };
            
            bool first = true;
            for (int i = 0; i < points.length; i += 2) {
                double x = (points[i] - OFFSET) * scale + offset_x;
                double y = (points[i+1] - OFFSET) * scale + offset_y;
                
                if (first) {
                    cr.move_to(x, y);
                    first = false;
                } else {
                    cr.line_to(x, y);
                }
            }
            
            cr.fill();
            cr.restore();
        }
        
        private void draw_thumbnail_border(Cairo.Context cr, Gdk.RGBA color) {
            double x = 0.38663504 * scale + offset_x;
            double y = 2.1540117 * scale + offset_y;
            double w = CANVAS_WIDTH * scale;
            double h = CANVAS_HEIGHT * scale;
            double r = 59.995388 * scale;
            
            cr.set_source_rgba(color.red, color.green, color.blue, 0.555004);
            cr.set_line_width(4.30802 * scale);
            cr.set_line_join(Cairo.LineJoin.ROUND);
            
            draw_rounded_rectangle(cr, x, y, w, h, r);
            cr.stroke();
        }
        
        private void draw_rounded_rectangle(Cairo.Context cr, double x, double y, 
                                             double w, double h, double r) {
            if (r <= 0) {
                cr.rectangle(x, y, w, h);
                return;
            }
            
            cr.move_to(x + r, y);
            cr.line_to(x + w - r, y);
            cr.curve_to(x + w - r/2, y, x + w, y + r/2, x + w, y + r);
            cr.line_to(x + w, y + h - r);
            cr.curve_to(x + w, y + h - r/2, x + w - r/2, y + h, x + w - r, y + h);
            cr.line_to(x + r, y + h);
            cr.curve_to(x + r/2, y + h, x, y + h - r/2, x, y + h - r);
            cr.line_to(x, y + r);
            cr.curve_to(x, y + r/2, x + r/2, y, x + r, y);
            cr.close_path();
        }
        
        private Gdk.RGBA parse_hex_color(string hex_str) {
            var color = Gdk.RGBA() { alpha = 1.0f };
            string hex = hex_str;
            
            if (hex.has_prefix("#")) {
                hex = hex.substring(1);
            }
            
            if (hex.length == 6) {
                uint32 rgb = 0;
                for (int i = 0; i < 6; i++) {
                    char c = hex[i];
                    uint32 val = 0;
                    if (c >= '0' && c <= '9') val = (uint32)(c - '0');
                    else if (c >= 'A' && c <= 'F') val = (uint32)(c - 'A' + 10);
                    else if (c >= 'a' && c <= 'f') val = (uint32)(c - 'a' + 10);
                    rgb = (rgb << 4) | val;
                }
                color.red = (float)((rgb >> 16) & 0xFF) / 255.0f;
                color.green = (float)((rgb >> 8) & 0xFF) / 255.0f;
                color.blue = (float)(rgb & 0xFF) / 255.0f;
            }
            
            return color;
        }
        
		public void clear_cache() {
    			ThumbnailCache.get_default().clear();
    			message("ThumbnailRenderer: Thumbnail cache cleared");
		}
        
        ~ThumbnailRenderer() {
            message("ThumbnailRenderer: Destroyed");
        }
    }
}
