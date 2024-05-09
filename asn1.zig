const std = @import("std");
const string = []const u8;
const assert = std.debug.assert;

pub const Tag = enum(u8) {
    // zig fmt: off
    end_of_content      = @as(u8, 0) | @intFromEnum(PC.primitive),
    boolean             = @as(u8, 1) | @intFromEnum(PC.primitive),
    integer             = @as(u8, 2) | @intFromEnum(PC.primitive),
    bit_string          = @as(u8, 3) | @intFromEnum(PC.primitive),
    octet_string        = @as(u8, 4) | @intFromEnum(PC.primitive),
    null                = @as(u8, 5) | @intFromEnum(PC.primitive),
    object_identifier   = @as(u8, 6) | @intFromEnum(PC.primitive),
    object_descriptor   = @as(u8, 7) | @intFromEnum(PC.primitive),
    external_type       = @as(u8, 8) | @intFromEnum(PC.primitive),
    real_type           = @as(u8, 9) | @intFromEnum(PC.primitive),
    enumerated_type     = @as(u8,10) | @intFromEnum(PC.primitive),
    embedded_pdv        = @as(u8,11) | @intFromEnum(PC.primitive),
    utf8_string         = @as(u8,12) | @intFromEnum(PC.primitive),
    relative_oid        = @as(u8,13) | @intFromEnum(PC.primitive),
    time                = @as(u8,14) | @intFromEnum(PC.primitive),
    _reserved2          = @as(u8,15) | @intFromEnum(PC.primitive),
    sequence            = @as(u8,16) | @intFromEnum(PC.constructed),
    set                 = @as(u8,17) | @intFromEnum(PC.constructed),
    numeric_string      = @as(u8,18) | @intFromEnum(PC.primitive),
    printable_string    = @as(u8,19) | @intFromEnum(PC.primitive),
    teletex_string      = @as(u8,20) | @intFromEnum(PC.primitive),
    videotex_string     = @as(u8,21) | @intFromEnum(PC.primitive),
    ia5_string          = @as(u8,22) | @intFromEnum(PC.primitive),
    utc_time            = @as(u8,23) | @intFromEnum(PC.primitive),
    generalized_time    = @as(u8,24) | @intFromEnum(PC.primitive),
    graphic_string      = @as(u8,25) | @intFromEnum(PC.primitive),
    visible_string      = @as(u8,26) | @intFromEnum(PC.primitive),
    general_string      = @as(u8,27) | @intFromEnum(PC.primitive),
    universal_string    = @as(u8,28) | @intFromEnum(PC.primitive),
    unrestricted_string = @as(u8,29) | @intFromEnum(PC.primitive),
    bmp_string          = @as(u8,30) | @intFromEnum(PC.primitive),
    date                = @as(u8,31) | @intFromEnum(PC.primitive),
    _,

    
    const PC = enum(u8) {
        primitive   = 0b00000000,
        constructed = 0b00100000,
    };

    const Class = enum(u8) {
        universal   = 0b00000000,
        application = 0b01000000,
        context     = 0b10000000,
        private     = 0b11000000,
    };
    // zig fmt: on

    pub fn int(tag: Tag) u8 {
        return @intFromEnum(tag);
    }

    pub fn extra(pc: PC, class: Class, ty: u5) Tag {
        var res: u8 = ty;
        res |= @intFromEnum(pc);
        res |= @intFromEnum(class);
        return @enumFromInt(res);
    }

    pub fn read(reader: anytype) !Tag {
        return @enumFromInt(try reader.readByte());
    }
};

pub const Length = packed struct(u8) {
    len: u7,
    form: enum(u1) { short, long },

    pub fn read(reader: anytype) !u64 {
        const octet: Length = @bitCast(try reader.readByte());
        switch (octet.form) {
            .short => return octet.len,
            .long => {
                var res: u64 = 0;
                assert(octet.len <= 8); // long form length exceeds bounds of u64
                assert(octet.len > 0); // TODO indefinite form
                for (0..octet.len) |i| {
                    res |= (@as(u64, try reader.readByte()) << @as(u6, @intCast(8 * (octet.len - 1 - @as(u6, @intCast(i))))));
                }
                return res;
            },
        }
    }
};

fn expectTag(reader: anytype, tag: Tag) !void {
    const actual = try Tag.read(reader);
    if (actual != tag) return error.UnexpectedTag;
}

fn expectLength(reader: anytype, len: u64) !void {
    const actual = try Length.read(reader);
    if (actual != len) return error.UnexpectedLength;
}

pub fn readBoolean(reader: anytype) !bool {
    try expectTag(reader, .boolean);
    try expectLength(reader, 1);
    return (try reader.readByte()) > 0;
}

pub fn readInt(reader: anytype, comptime Int: type) !Int {
    comptime assert(@bitSizeOf(Int) % 8 == 0);
    const L2Int = std.math.Log2Int(Int);
    try expectTag(reader, .integer);
    const len = try Length.read(reader);
    assert(len <= 8); // TODO implement readIntBig
    assert(len > 0);
    assert(len <= @sizeOf(Int));
    var res: Int = 0;
    for (0..len) |i| {
        res |= (@as(Int, try reader.readByte()) << @as(L2Int, @intCast(8 * (len - 1 - @as(L2Int, @intCast(i))))));
    }
    return res;
}

pub fn encodeKrbAsReq(buffer: []u8, user_name: []const u8, realm: []const u8) ![]const u8 {
    std.debug.assert(user_name.len <= 100);
    std.debug.assert(realm.len <= 100);

    var fbs_write = std.io.fixedBufferStream(buffer);
    const w = fbs_write.writer();

    // Length of the entire packet
    try w.writeInt(u32, 0xffff_ffff, .big); // Dummy value, computed later

    // AS-REQ          ::= [APPLICATION 10] KDC-REQ
    try w.writeByte(Tag.extra(.constructed, .application, 10).int());
    try w.writeByte(0b1000_0010); // 2-bytes length
    try w.writeInt(u16, 0xffff, .big); // Dummy value, computed later, offset: 6

    // KDC-REQ         ::= SEQUENCE {
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(0b1000_0010); // 2-bytes length
    try w.writeInt(u16, 0xffff, .big); // Dummy value, computed later, offset: 10

    //        pvno            [1] INTEGER (5) , (version)
    try w.writeByte(Tag.extra(.constructed, .context, 1).int());
    try w.writeByte(3);
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(5);

    //        msg-type        [2] INTEGER (10 -- AS -- | 12 -- TGS --),
    try w.writeByte(Tag.extra(.constructed, .context, 2).int());
    try w.writeByte(3);
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(10);

    //        req-body        [4] KDC-REQ-BODY
    try w.writeByte(Tag.extra(.constructed, .context, 4).int());
    try w.writeByte(0b1000_0010); // 2-bytes length
    try w.writeInt(u16, 0xffff, .big); // Dummy value, computed later, offset: 24

    // KDC-REQ-BODY    ::= SEQUENCE {
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(0b1000_0010); // 2-bytes length
    try w.writeInt(u16, 0xffff, .big); // Dummy value, computed later, offset: 28

    //        kdc-options             [0] KDCOptions,
    try w.writeByte(Tag.extra(.constructed, .context, 0).int());
    try w.writeByte(7);
    try w.writeByte(@intFromEnum(Tag.bit_string));
    try w.writeByte(5);
    try w.writeByte(0); // padding
    try w.writeInt(u32, 0x40000000, .big);

    //        cname                   [1] PrincipalName OPTIONAL
    try w.writeByte(Tag.extra(.constructed, .context, 1).int());
    try w.writeByte(@intCast(user_name.len + 13));
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(@intCast(user_name.len + 11));
    try w.writeByte(Tag.extra(.constructed, .context, 0).int());
    try w.writeByte(3);
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(1); // type == 1 (NT-PRINCIPAL)
    try w.writeByte(Tag.extra(.constructed, .context, 1).int());
    try w.writeByte(@intCast(user_name.len + 4));
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(@intCast(user_name.len + 2));
    try w.writeByte(@intFromEnum(Tag.general_string));
    try w.writeByte(@intCast(user_name.len));
    try w.writeAll(user_name);

    //        realm                   [2] Realm
    try w.writeByte(Tag.extra(.constructed, .context, 2).int());
    try w.writeByte(@intCast(realm.len + 2));
    try w.writeByte(@intFromEnum(Tag.general_string));
    try w.writeByte(@intCast(realm.len));
    try w.writeAll(realm);

    //        sname                   [3] PrincipalName OPTIONAL,
    try w.writeByte(Tag.extra(.constructed, .context, 3).int());
    try w.writeByte(@intCast(realm.len + 21));
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(@intCast(realm.len + 19));
    try w.writeByte(Tag.extra(.constructed, .context, 0).int());
    try w.writeByte(3);
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(2); // type == 2 (NT-SRV-INST)
    try w.writeByte(Tag.extra(.constructed, .context, 1).int());
    try w.writeByte(@intCast(realm.len + 12));
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(@intCast(realm.len + 10));
    try w.writeByte(@intFromEnum(Tag.general_string));
    try w.writeByte("krbtgt".len);
    try w.writeAll("krbtgt");
    try w.writeByte(@intFromEnum(Tag.general_string));
    try w.writeByte(@intCast(realm.len));
    try w.writeAll(realm);

    //        till                    [5] KerberosTime,
    try w.writeByte(Tag.extra(.constructed, .context, 5).int());
    try w.writeByte(17);
    try w.writeByte(@intFromEnum(Tag.generalized_time));
    try w.writeByte(15);
    try w.writeAll("19700101000000Z"); // No expiration date

    //        nonce                   [7] UInt32,
    try w.writeByte(Tag.extra(.constructed, .context, 7).int());
    try w.writeByte(6);
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(4);
    try w.writeInt(u32, 155874945, .big);

    //        etype                   [8] SEQUENCE OF Int32 -- EncryptionType
    try w.writeByte(Tag.extra(.constructed, .context, 8).int());
    try w.writeByte(14);
    try w.writeByte(@intFromEnum(Tag.sequence));
    try w.writeByte(12);
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(18); //      { ['aes256-cts-hmac-sha1-96'] = 18 },
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(17); //      { ['aes128-cts-hmac-sha1-96'] = 17 },
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(16); //      { ['des3-cbc-sha1'] = 16 },
    try w.writeByte(@intFromEnum(Tag.integer));
    try w.writeByte(1);
    try w.writeByte(23); //      { ['rc4-hmac'] = 23 },

    // Fixups
    const total_len: u32 = @intCast(fbs_write.getWritten().len);
    std.mem.writeInt(u32, buffer[0..4], total_len - 4, .big);
    std.mem.writeInt(u16, buffer[6..8], @intCast(total_len - 8), .big);
    std.mem.writeInt(u16, buffer[10..12], @intCast(total_len - 12), .big);
    std.mem.writeInt(u16, buffer[24..26], @intCast(total_len - 26), .big);
    std.mem.writeInt(u16, buffer[28..30], @intCast(total_len - 30), .big);

    return fbs_write.getWritten();
}

// TODO readIntBig

// TODO enumerated value

// TODO real value

// TODO bitstring value

// TODO octetstring value

pub fn readNull(reader: anytype) !void {
    try expectTag(reader, .null);
    try expectLength(reader, 0);
}

// TODO sequence value

// TODO sequence-of value

// TODO set value

// TODO set-of value

// TODO choice value

// TODO value of a prefixed type

// TODO value of an open type

// TODO instance-of value

// TODO value of the embedded-pdv type

// TODO value of the external type

// TODO object identifier value

// TODO relative object identifier value

// TODO OID internationalized resource identifier value

// TODO relative OID internationalized resource identifier value

// TODO values of the restricted character string types

// TODO values of the unrestricted character string type
