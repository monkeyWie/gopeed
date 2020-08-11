package torrent

import (
	"github.com/monkeyWie/gopeed-core/protocol/bt/metainfo"
	"github.com/monkeyWie/gopeed-core/protocol/bt/peer"
	log "github.com/sirupsen/logrus"
	"testing"
)

func init() {
	log.SetLevel(log.DebugLevel)
}

func TestTorrent_Download(t *testing.T) {
	torrent := buildTorrent()
	torrent.Download("e:/testbt/download")
}

func buildTorrent() *Torrent {
	// metaInfo, err := metainfo.ParseFromFile("../testdata/Game.of.Thrones.S08E05.720p.WEB.H264-MEMENTO.torrent")
	metaInfo, err := metainfo.ParseFromFile("../testdata/office.torrent")
	if err != nil {
		panic(err)
	}

	metaInfo.AnnounceList[0] = append(metaInfo.AnnounceList[0], []string{
		"udp://tracker.coppersurfer.tk:6969/announce",
		"udp://tracker.leechers-paradise.org:6969/announce",
		"udp://tracker.opentrackr.org:1337/announce",
		"udp://p4p.arenabg.com:1337/announce",
		"udp://9.rarbg.to:2710/announce",
		"udp://9.rarbg.me:2710/announce",
		"udp://tracker.internetwarriors.net:1337/announce",
		"udp://exodus.desync.com:6969/announce",
		"udp://tracker.tiny-vps.com:6969/announce",
		"udp://tracker.sbsub.com:2710/announce",
		"udp://retracker.lanta-net.ru:2710/announce",
		"udp://open.stealth.si:80/announce",
		"udp://open.demonii.si:1337/announce",
		"udp://tracker.torrent.eu.org:451/announce",
		"udp://tracker.moeking.me:6969/announce",
		"udp://tracker.cyberia.is:6969/announce",
		"udp://denis.stalker.upeer.me:6969/announce",
		"udp://ipv4.tracker.harry.lu:80/announce",
		"udp://explodie.org:6969/announce",
		"udp://zephir.monocul.us:6969/announce",
		"udp://xxxtor.com:2710/announce",
		"udp://valakas.rollo.dnsabr.com:2710/announce",
		"udp://tracker.zerobytes.xyz:1337/announce",
		"udp://tracker.yoshi210.com:6969/announce",
		"udp://tracker.uw0.xyz:6969/announce",
		"udp://tracker.swateam.org.uk:2710/announce",
		"udp://tracker.nyaa.uk:6969/announce",
		"udp://tracker.filemail.com:6969/announce",
		"udp://tracker.ds.is:6969/announce",
		"udp://retracker.sevstar.net:2710/announce",
		"udp://retracker.netbynet.ru:2710/announce",
		"udp://retracker.akado-ural.ru:80/announce",
		"udp://opentracker.i2p.rocks:6969/announce",
		"udp://opentor.org:2710/announce",
		"udp://open.nyap2p.com:6969/announce",
		"udp://chihaya.toss.li:9696/announce",
		"udp://bt2.archive.org:6969/announce",
		"udp://bt1.archive.org:6969/announce",
		"udp://www.loushao.net:8080/announce",
		"udp://tracker4.itzmx.com:2710/announce",
		"udp://tracker3.itzmx.com:6961/announce",
		"udp://tracker2.itzmx.com:6961/announce",
		"udp://tracker.lelux.fi:6969/announce",
		"udp://tracker.kamigami.org:2710/announce",
		"udp://tracker.dler.org:6969/announce",
		"udp://tr.bangumi.moe:6969/announce",
		"udp://qg.lorzl.gq:2710/announce",
		"udp://bt2.54new.com:8080/announce",
	}...)
	return NewTorrent(peer.GenPeerID(), metaInfo)
}
