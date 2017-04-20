defmodule Exts.Parser.Pes do
  use Bitwise

  def pts_dts(<<_marker::2, _scramble::2, _priority::1, _dai::1, _copyright::1, _original::1,
                   # pts = 1 and dts =1
                   1::1, 1::1, _escr::1, _esrate::1, _dsm::1, _addcopy::1, _crc::1, _ext::1, _pes_header_len::8,
                   # pts field
                   _::4, pts32_30::3, _::1, pts29_15::15, _::1, pts14_00::15, _::1,
                   # dts field
                   _::4, dts32_30::3, _::1, dts29_15::15, _::1, dts14_00::15, _::1,
                   _rest::binary >>) do
    pts = (pts32_30 <<< 30) + (pts29_15 <<< 15) + pts14_00
    dts = (dts32_30 <<< 30) + (dts29_15 <<< 15) + dts14_00
    {pts * 300, dts * 300}
  end

  def pts_dts(<<_marker::2, _scramble::2, _priority::1, _dai::1, _copyright::1, _original::1,
                   # pts = 1 and dts =0
                   1::1, 0::1, _escr::1, _esrate::1, _dsm::1, _addcopy::1, _crc::1, _ext::1, _pes_header_len::8,
                   # pts field
                   _::4, pts32_30::3, _::1, pts29_15::15, _::1, pts14_00::15, _::1,
                   _rest::binary >>) do
    pts = (pts32_30 <<< 30) + (pts29_15 <<< 15) + pts14_00
    {pts * 300, pts * 300}
  end

  def pts_dts(_) do
    {-1, -1}
  end
end
