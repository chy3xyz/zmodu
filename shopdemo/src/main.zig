const std = @import("std");
const zigmodu = @import("zigmodu");

const ad = @import("modules/ad/root.zig");
const admin = @import("modules/admin/root.zig");
const advance = @import("modules/advance/root.zig");
const agent = @import("modules/agent/root.zig");
const app_mod = @import("modules/app/root.zig");
const article = @import("modules/article/root.zig");
const assemble = @import("modules/assemble/root.zig");
const balance = @import("modules/balance/root.zig");
const bargain = @import("modules/bargain/root.zig");
const buy = @import("modules/buy/root.zig");
const category = @import("modules/category/root.zig");
const center = @import("modules/center/root.zig");
const chat = @import("modules/chat/root.zig");
const comment = @import("modules/comment/root.zig");
const coupon = @import("modules/coupon/root.zig");
const delivery = @import("modules/delivery/root.zig");
const express = @import("modules/express/root.zig");
const image = @import("modules/image/root.zig");
const live = @import("modules/live/root.zig");
const lottery = @import("modules/lottery/root.zig");
const message = @import("modules/message/root.zig");
const order = @import("modules/order/root.zig");
const page = @import("modules/page/root.zig");
const plus = @import("modules/plus/root.zig");
const point = @import("modules/point/root.zig");
const printer = @import("modules/printer/root.zig");
const product = @import("modules/product/root.zig");
const region = @import("modules/region/root.zig");
const register = @import("modules/register/root.zig");
const return_mod = @import("modules/return/root.zig");
const seckill = @import("modules/seckill/root.zig");
const setting = @import("modules/setting/root.zig");
const shop = @import("modules/shop/root.zig");
const sms = @import("modules/sms/root.zig");
const spec = @import("modules/spec/root.zig");
const store = @import("modules/store/root.zig");
const supplier = @import("modules/supplier/root.zig");
const table = @import("modules/table/root.zig");
const tag = @import("modules/tag/root.zig");
const upload = @import("modules/upload/root.zig");
const user = @import("modules/user/root.zig");
const version = @import("modules/version/root.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const env = init.environ_map;

    // -- Config --
    const db_host = env.get("DB_HOST") orelse "127.0.0.1";
    const db_port = env.get("DB_PORT") orelse "3306";
    const db_user = env.get("DB_USER") orelse "root";
    const db_pass = env.get("DB_PASS") orelse "";
    const db_name = env.get("DB_NAME") orelse "heysen";

    const db_cfg = zigmodu.data.sqlx.Config{
        .driver = .mysql, .host = db_host, .port = std.fmt.parseInt(u16, db_port, 10) catch 3306,
        .database = db_name, .username = db_user, .password = db_pass,
        .max_open_conns = 10, .max_idle_conns = 5,
    };
    var db_client = try zigmodu.data.sqlx.Client.open(allocator, init.io, db_cfg);
    defer db_client.deinit();
    std.log.info("DB connected: {s}@{s}:{s}/{s}", .{ db_user, db_host, db_port, db_name });

    const backend = zigmodu.data.SqlxBackend{ .allocator = allocator, .client = &db_client };

    // -- Persistence --
    var ad_p = ad.persistence.AdPersistence.init(backend);
    var admin_p = admin.persistence.AdminPersistence.init(backend);
    var advance_p = advance.persistence.AdvancePersistence.init(backend);
    var agent_p = agent.persistence.AgentPersistence.init(backend);
    var app_p = app_mod.persistence.AppPersistence.init(backend);
    var article_p = article.persistence.ArticlePersistence.init(backend);
    var assemble_p = assemble.persistence.AssemblePersistence.init(backend);
    var balance_p = balance.persistence.BalancePersistence.init(backend);
    var bargain_p = bargain.persistence.BargainPersistence.init(backend);
    var buy_p = buy.persistence.BuyPersistence.init(backend);
    var category_p = category.persistence.CategoryPersistence.init(backend);
    var center_p = center.persistence.CenterPersistence.init(backend);
    var chat_p = chat.persistence.ChatPersistence.init(backend);
    var comment_p = comment.persistence.CommentPersistence.init(backend);
    var coupon_p = coupon.persistence.CouponPersistence.init(backend);
    var delivery_p = delivery.persistence.DeliveryPersistence.init(backend);
    var express_p = express.persistence.ExpressPersistence.init(backend);
    var image_p = image.persistence.ImagePersistence.init(backend);
    var live_p = live.persistence.LivePersistence.init(backend);
    var lottery_p = lottery.persistence.LotteryPersistence.init(backend);
    var message_p = message.persistence.MessagePersistence.init(backend);
    var order_p = order.persistence.OrderPersistence.init(backend);
    var page_p = page.persistence.PagePersistence.init(backend);
    var plus_p = plus.persistence.PlusPersistence.init(backend);
    var point_p = point.persistence.PointPersistence.init(backend);
    var printer_p = printer.persistence.PrinterPersistence.init(backend);
    var product_p = product.persistence.ProductPersistence.init(backend);
    var region_p = region.persistence.RegionPersistence.init(backend);
    var register_p = register.persistence.RegisterPersistence.init(backend);
    var return_p = return_mod.persistence.ReturnPersistence.init(backend);
    var seckill_p = seckill.persistence.SeckillPersistence.init(backend);
    var setting_p = setting.persistence.SettingPersistence.init(backend);
    var shop_p = shop.persistence.ShopPersistence.init(backend);
    var sms_p = sms.persistence.SmsPersistence.init(backend);
    var spec_p = spec.persistence.SpecPersistence.init(backend);
    var store_p = store.persistence.StorePersistence.init(backend);
    var supplier_p = supplier.persistence.SupplierPersistence.init(backend);
    var table_p = table.persistence.TablePersistence.init(backend);
    var tag_p = tag.persistence.TagPersistence.init(backend);
    var upload_p = upload.persistence.UploadPersistence.init(backend);
    var user_p = user.persistence.UserPersistence.init(backend);
    var version_p = version.persistence.VersionPersistence.init(backend);

    // -- Service --
    var ad_svc = ad.service.AdService.init(&ad_p);
    var admin_svc = admin.service.AdminService.init(&admin_p);
    var advance_svc = advance.service.AdvanceService.init(&advance_p);
    var agent_svc = agent.service.AgentService.init(&agent_p);
    var app_svc = app_mod.service.AppService.init(&app_p);
    var article_svc = article.service.ArticleService.init(&article_p);
    var assemble_svc = assemble.service.AssembleService.init(&assemble_p);
    var balance_svc = balance.service.BalanceService.init(&balance_p);
    var bargain_svc = bargain.service.BargainService.init(&bargain_p);
    var buy_svc = buy.service.BuyService.init(&buy_p);
    var category_svc = category.service.CategoryService.init(&category_p);
    var center_svc = center.service.CenterService.init(&center_p);
    var chat_svc = chat.service.ChatService.init(&chat_p);
    var comment_svc = comment.service.CommentService.init(&comment_p);
    var coupon_svc = coupon.service.CouponService.init(&coupon_p);
    var delivery_svc = delivery.service.DeliveryService.init(&delivery_p);
    var express_svc = express.service.ExpressService.init(&express_p);
    var image_svc = image.service.ImageService.init(&image_p);
    var live_svc = live.service.LiveService.init(&live_p);
    var lottery_svc = lottery.service.LotteryService.init(&lottery_p);
    var message_svc = message.service.MessageService.init(&message_p);
    var order_svc = order.service.OrderService.init(&order_p);
    var page_svc = page.service.PageService.init(&page_p);
    var plus_svc = plus.service.PlusService.init(&plus_p);
    var point_svc = point.service.PointService.init(&point_p);
    var printer_svc = printer.service.PrinterService.init(&printer_p);
    var product_svc = product.service.ProductService.init(&product_p);
    var region_svc = region.service.RegionService.init(&region_p);
    var register_svc = register.service.RegisterService.init(&register_p);
    var return_svc = return_mod.service.ReturnService.init(&return_p);
    var seckill_svc = seckill.service.SeckillService.init(&seckill_p);
    var setting_svc = setting.service.SettingService.init(&setting_p);
    var shop_svc = shop.service.ShopService.init(&shop_p);
    var sms_svc = sms.service.SmsService.init(&sms_p);
    var spec_svc = spec.service.SpecService.init(&spec_p);
    var store_svc = store.service.StoreService.init(&store_p);
    var supplier_svc = supplier.service.SupplierService.init(&supplier_p);
    var table_svc = table.service.TableService.init(&table_p);
    var tag_svc = tag.service.TagService.init(&tag_p);
    var upload_svc = upload.service.UploadService.init(&upload_p);
    var user_svc = user.service.UserService.init(&user_p);
    var version_svc = version.service.VersionService.init(&version_p);

    // -- API --
    var ad_api = ad.api.AdApi.init(&ad_svc);
    var admin_api = admin.api.AdminApi.init(&admin_svc);
    var advance_api = advance.api.AdvanceApi.init(&advance_svc);
    var agent_api = agent.api.AgentApi.init(&agent_svc);
    var app_api = app_mod.api.AppApi.init(&app_svc);
    var article_api = article.api.ArticleApi.init(&article_svc);
    var assemble_api = assemble.api.AssembleApi.init(&assemble_svc);
    var balance_api = balance.api.BalanceApi.init(&balance_svc);
    var bargain_api = bargain.api.BargainApi.init(&bargain_svc);
    var buy_api = buy.api.BuyApi.init(&buy_svc);
    var category_api = category.api.CategoryApi.init(&category_svc);
    var center_api = center.api.CenterApi.init(&center_svc);
    var chat_api = chat.api.ChatApi.init(&chat_svc);
    var comment_api = comment.api.CommentApi.init(&comment_svc);
    var coupon_api = coupon.api.CouponApi.init(&coupon_svc);
    var delivery_api = delivery.api.DeliveryApi.init(&delivery_svc);
    var express_api = express.api.ExpressApi.init(&express_svc);
    var image_api = image.api.ImageApi.init(&image_svc);
    var live_api = live.api.LiveApi.init(&live_svc);
    var lottery_api = lottery.api.LotteryApi.init(&lottery_svc);
    var message_api = message.api.MessageApi.init(&message_svc);
    var order_api = order.api.OrderApi.init(&order_svc);
    var page_api = page.api.PageApi.init(&page_svc);
    var plus_api = plus.api.PlusApi.init(&plus_svc);
    var point_api = point.api.PointApi.init(&point_svc);
    var printer_api = printer.api.PrinterApi.init(&printer_svc);
    var product_api = product.api.ProductApi.init(&product_svc);
    var region_api = region.api.RegionApi.init(&region_svc);
    var register_api = register.api.RegisterApi.init(&register_svc);
    var return_api = return_mod.api.ReturnApi.init(&return_svc);
    var seckill_api = seckill.api.SeckillApi.init(&seckill_svc);
    var setting_api = setting.api.SettingApi.init(&setting_svc);
    var shop_api = shop.api.ShopApi.init(&shop_svc);
    var sms_api = sms.api.SmsApi.init(&sms_svc);
    var spec_api = spec.api.SpecApi.init(&spec_svc);
    var store_api = store.api.StoreApi.init(&store_svc);
    var supplier_api = supplier.api.SupplierApi.init(&supplier_svc);
    var table_api = table.api.TableApi.init(&table_svc);
    var tag_api = tag.api.TagApi.init(&tag_svc);
    var upload_api = upload.api.UploadApi.init(&upload_svc);
    var user_api = user.api.UserApi.init(&user_svc);
    var version_api = version.api.VersionApi.init(&version_svc);
    // -- Auth --
    const jwt_secret = env.get("JWT_SECRET") orelse "changeme-in-production";
    _ = jwt_secret;
    // TODO: wire zigmodu.security.auth with JWT secret
    // server.addMiddleware(.{ .func = zigmodu.security.auth.jwtAuth(jwt_secret) });


    // -- HTTP Server --
    const http_port: u16 = if (env.get("HTTP_PORT")) |p| std.fmt.parseInt(u16, p, 10) catch 8080 else 8080;
    var server = zigmodu.http.Server.initWithConfig(init.io, allocator, .{ .port = http_port });
    defer server.deinit();
    server.withGracefulDrain(zigmodu.getInFlightCounter());

    // -- Health Checks --
    var health_endpoint = zigmodu.HealthEndpoint.init(allocator);
    defer health_endpoint.deinit();
    try health_endpoint.registerCheck("liveness", "Process liveness", zigmodu.HealthEndpoint.alwaysUp);
    try health_endpoint.registerCheckWithContext("database", "DB connectivity", zigmodu.HealthEndpoint.databaseCheck, @ptrCast(&db_client));
    var root = server.group("/api");
    try root.get("/health/live", healthLive, null);
    try root.get("/health/ready", healthReady, null);

    try ad_api.registerRoutes(&root);
    try admin_api.registerRoutes(&root);
    try advance_api.registerRoutes(&root);
    try agent_api.registerRoutes(&root);
    try app_api.registerRoutes(&root);
    try article_api.registerRoutes(&root);
    try assemble_api.registerRoutes(&root);
    try balance_api.registerRoutes(&root);
    try bargain_api.registerRoutes(&root);
    try buy_api.registerRoutes(&root);
    try category_api.registerRoutes(&root);
    try center_api.registerRoutes(&root);
    try chat_api.registerRoutes(&root);
    try comment_api.registerRoutes(&root);
    try coupon_api.registerRoutes(&root);
    try delivery_api.registerRoutes(&root);
    try express_api.registerRoutes(&root);
    try image_api.registerRoutes(&root);
    try live_api.registerRoutes(&root);
    try lottery_api.registerRoutes(&root);
    try message_api.registerRoutes(&root);
    try order_api.registerRoutes(&root);
    try page_api.registerRoutes(&root);
    try plus_api.registerRoutes(&root);
    try point_api.registerRoutes(&root);
    try printer_api.registerRoutes(&root);
    try product_api.registerRoutes(&root);
    try region_api.registerRoutes(&root);
    try register_api.registerRoutes(&root);
    try return_api.registerRoutes(&root);
    try seckill_api.registerRoutes(&root);
    try setting_api.registerRoutes(&root);
    try shop_api.registerRoutes(&root);
    try sms_api.registerRoutes(&root);
    try spec_api.registerRoutes(&root);
    try store_api.registerRoutes(&root);
    try supplier_api.registerRoutes(&root);
    try table_api.registerRoutes(&root);
    try tag_api.registerRoutes(&root);
    try upload_api.registerRoutes(&root);
    try user_api.registerRoutes(&root);
    try version_api.registerRoutes(&root);

    // -- EventBus --
    var event_bus = zigmodu.EventBus(struct { id: i64 }).init(allocator);
    defer event_bus.deinit();

    // -- Resilience --
    var breaker = try zigmodu.CircuitBreaker.init(allocator, "db", .{ .failure_threshold = 5, .success_threshold = 2, .timeout_seconds = 30, .half_open_max_calls = 3 });
    defer breaker.deinit();
    var limiter = try zigmodu.RateLimiter.init(allocator, "api", 1000, 100);
    defer limiter.deinit();

    // -- Cluster --
    const node_id = try std.fmt.allocPrint(allocator, "node-{d}", .{@as(u64, @intCast(std.time.epoch.unix))});
    var dist_bus = try zigmodu.DistributedEventBus.init(allocator, init.io, node_id);
    defer dist_bus.deinit();
    try dist_bus.start(9091);

    // -- Prometheus /metrics --
    var metrics = zigmodu.observability.PrometheusMetrics.init(allocator);
    defer metrics.deinit();
    try metrics.registerMetricsRoute(&server);

    // -- Lifecycle --
    var app = try zigmodu.Application.init(init.io, allocator, "shopdemo", .{ ad.module, admin.module, advance.module, agent.module, app_mod.module, article.module, assemble.module, balance.module, bargain.module, buy.module, category.module, center.module, chat.module, comment.module, coupon.module, delivery.module, express.module, image.module, live.module, lottery.module, message.module, order.module, page.module, plus.module, point.module, printer.module, product.module, region.module, register.module, return_mod.module, seckill.module, setting.module, shop.module, sms.module, spec.module, store.module, supplier.module, table.module, tag.module, upload.module, user.module, version.module, }, .{});
    defer app.deinit();

    try app.start();
    try server.start();
}

fn healthLive(ctx: *zigmodu.http.Context) !void {
    try ctx.json(200, "{\"status\":\"UP\"}");
}

fn healthReady(ctx: *zigmodu.http.Context) !void {
    try ctx.json(200, "{\"status\":\"UP\"}");
}
